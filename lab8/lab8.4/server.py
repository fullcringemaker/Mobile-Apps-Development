import asyncio
import contextlib
import json
import math
import time
from dataclasses import dataclass, field

from aiohttp import WSMsgType, web

HOST, PORT = "0.0.0.0", 8765
BALL_RADIUS, BALL_SPEED = 0.42, 6.5
WALL_X, WALL_BOTTOM, WALL_TOP = 14.0, -4.0, 26.0
WALL_NEAR, WALL_FAR = -16.0, 16.0
INPUT_TIMEOUT = 0.4

ALLOWED_ACTIONS = {
    f"{axis}_{direction}"
    for axis in ("x", "y", "z", "yaw", "pitch")
    for direction in ("plus", "minus")
}


@dataclass(frozen=True)
class V3:
    x: float
    y: float
    z: float

    def __add__(self, other):
        return V3(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other):
        return V3(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, value):
        return V3(self.x * value, self.y * value, self.z * value)

    def dot(self, other):
        return self.x * other.x + self.y * other.y + self.z * other.z

    @property
    def length(self):
        return math.sqrt(self.dot(self))

    def to_json(self):
        return [self.x, self.y, self.z]


def clamp(value, lower, upper):
    return max(lower, min(upper, value))


@dataclass
class Player:
    id: int
    connected: bool = False
    wants_grip: bool = False
    x: float = 0.0
    y: float = 0.0
    z: float = field(init=False)
    yaw: float = field(init=False)
    pitch: float = 0.0
    bend: float = 0.0
    last_input: float = 0.0
    actions: set = field(default_factory=set)

    def __post_init__(self):
        self.z = 5.0 if self.id == 1 else -5.0
        self.yaw = 20.0 if self.id == 1 else -20.0

    @property
    def gripped(self):
        return self.bend >= 12.0

    @property
    def basis(self):
        a, b = math.radians(self.yaw), math.radians(self.pitch)
        cy, sy, cp, sp = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
        return (
            V3(cy * cp, sp, -sy * cp),
            V3(-cy * sp, cp, sy * sp),
            V3(sy, 0, cy),
        )

    @property
    def center_offset(self):
        normal, up, side = self.basis
        return normal * -0.5 + up * 11.82 + side * -1.1

    @property
    def center(self):
        return V3(self.x, self.y, self.z) + self.center_offset

    def update(self, dt, now):
        if not self.connected:
            return

        if self.wants_grip:
            self.bend = min(12.0, self.bend + dt * 24.0)

        if not self.gripped:
            return

        active = self.actions if now - self.last_input <= INPUT_TIMEOUT else set()

        def delta(axis, speed):
            return (
                int(f"{axis}_plus" in active)
                - int(f"{axis}_minus" in active)
            ) * speed * dt

        self.x = clamp(self.x + delta("x", 7), -6.0, 8.0)
        self.yaw = clamp(self.yaw + delta("yaw", 45), -60.0, 60.0)
        self.pitch = clamp(self.pitch + delta("pitch", 45), -50.0, 50.0)

        offset = self.center_offset

        self.y = clamp(
            self.y + delta("y", 7),
            WALL_BOTTOM - offset.y,
            WALL_TOP - offset.y,
        )
        self.z = clamp(
            self.z + delta("z", 7),
            WALL_NEAR - offset.z,
            WALL_FAR - offset.z,
        )

    def to_json(self):
        return {
            "id": self.id,
            "connected": self.connected,
            "gripped": self.gripped,
            "x": self.x,
            "y": self.y,
            "z": self.z,
            "yaw": self.yaw,
            "pitch": self.pitch,
            "bend": self.bend,
        }


@dataclass
class Game:
    players: list = field(default_factory=lambda: [Player(1), Player(2)])
    position: V3 = V3(2, 11.82, -1.1)
    velocity: V3 = V3(0, 0, 0)
    phase: str = "waiting"
    next_server: int = 1

    @property
    def ready(self):
        return all(
            player.connected and player.gripped
            for player in self.players
        )

    def reset(self):
        self.phase = "waiting"
        self.velocity = V3(0, 0, 0)
        player = self.players[self.next_server - 1]
        self.position = player.center + player.basis[0] * 2

    def step(self, dt, now):
        for player in self.players:
            player.update(dt, now)

        if not self.ready:
            if self.phase == "playing":
                self.reset()
            return

        if self.phase == "waiting":
            player = self.players[self.next_server - 1]
            self.position = player.center + player.basis[0] * 2
            self.velocity = player.basis[0] * BALL_SPEED
            self.phase = "playing"

        remaining = dt

        while remaining > 1e-7 and self.phase == "playing":
            interval = min(remaining, 1 / 120)
            self.advance(interval)
            remaining -= interval

    def advance(self, dt):
        remaining = dt

        for _ in range(4):
            if remaining <= 1e-7:
                break

            end = self.position + self.velocity * remaining
            fraction, normal = 2.0, None

            if (
                self.velocity.x > 0
                and self.position.x <= WALL_X - BALL_RADIUS <= end.x
            ):
                hit_time = (
                    WALL_X - BALL_RADIUS - self.position.x
                ) / (end.x - self.position.x)

                hit = self.position + (end - self.position) * hit_time

                if (
                    WALL_BOTTOM <= hit.y <= WALL_TOP
                    and WALL_NEAR <= hit.z <= WALL_FAR
                ):
                    fraction, normal = hit_time, V3(-1, 0, 0)

            for player in self.players:
                if not player.connected or not player.gripped:
                    continue

                n, up, side = player.basis

                if self.velocity.dot(n) >= -1e-6:
                    continue

                d0 = (self.position - player.center).dot(n)
                d1 = (end - player.center).dot(n)

                if d0 < BALL_RADIUS or d1 > BALL_RADIUS:
                    continue

                hit_time = (d0 - BALL_RADIUS) / (d0 - d1)

                relative = (
                    self.position
                    + (end - self.position) * hit_time
                    - player.center
                )

                vertical = relative.dot(up) / (3.3 + BALL_RADIUS)
                horizontal = relative.dot(side) / (2.55 + BALL_RADIUS)

                if (
                    vertical * vertical + horizontal * horizontal <= 1
                    and hit_time < fraction
                ):
                    fraction, normal = hit_time, n

            if normal is None:
                self.position = end
                break

            self.position = (
                self.position
                + (end - self.position) * fraction
                + normal * 1e-5
            )

            self.velocity = (
                self.velocity
                - normal * (2 * self.velocity.dot(normal))
            )

            remaining *= 1 - fraction

        if not (
            -10 <= self.position.x <= 22
            and -15 <= self.position.y <= 36
            and -24 <= self.position.z <= 24
        ):
            self.phase = "out"
            self.velocity = V3(0, 0, 0)
            self.next_server = 3 - self.next_server

    def state(self):
        return {
            "type": "state",
            "phase": self.phase,
            "players": [player.to_json() for player in self.players],
            "ball": self.position.to_json(),
        }


def create_app():
    game = Game()
    connections = {}
    app = web.Application()

    async def websocket(request):
        socket = web.WebSocketResponse(
            heartbeat=10,
            max_msg_size=8192,
            compress=False,
        )

        await socket.prepare(request)
        number = None

        try:
            first = await socket.receive(timeout=8)

            if first.type != WSMsgType.TEXT:
                return socket

            data = json.loads(first.data)

            if not isinstance(data, dict) or data.get("type") != "join":
                return socket

            number = data.get("player")

            if type(number) is not int or number not in (1, 2):
                number = None
                return socket

            if number in connections and not connections[number].closed:
                await socket.send_json({"type": "error"})
                return socket

            connections[number] = socket

            player = Player(number)
            player.connected = True
            game.players[number - 1] = player

            await socket.send_json({
                "type": "welcome",
                "player": number,
            })

            async for message in socket:
                if message.type != WSMsgType.TEXT:
                    break

                data = message.json()

                if not isinstance(data, dict):
                    break

                if data.get("type") == "input":
                    actions = data.get("actions")

                    if isinstance(actions, list):
                        player.actions = {
                            a
                            for a in actions
                            if isinstance(a, str) and a in ALLOWED_ACTIONS
                        }
                        player.last_input = time.monotonic()

                elif data.get("type") == "grab":
                    player.wants_grip = True

                elif data.get("type") == "reset":
                    game.reset()

        except (ValueError, TimeoutError, ConnectionError, RuntimeError):
            pass

        finally:
            if number is not None and connections.get(number) is socket:
                del connections[number]

                player = game.players[number - 1]
                player.connected = False
                player.actions.clear()
                player.bend = 0.0
                player.wants_grip = False

                game.reset()

            await socket.close()

        return socket

    async def update():
        previous = time.monotonic()
        frame = 0

        while True:
            now = time.monotonic()
            dt, previous = clamp(now - previous, 0.0, 0.05), now

            if connections:
                game.step(dt, now)
                frame += 1

                if frame % 2 == 0:
                    state = json.dumps(
                        game.state(),
                        separators=(",", ":"),
                    )

                    for socket in list(connections.values()):
                        try:
                            await asyncio.wait_for(
                                socket.send_str(state),
                                timeout=1,
                            )
                        except (
                            ConnectionError,
                            TimeoutError,
                            RuntimeError,
                        ):
                            await socket.close()

            await asyncio.sleep(
                max(0, 1 / 60 - (time.monotonic() - now))
            )

    async def running(app):
        task = asyncio.create_task(update())

        try:
            yield
        finally:
            task.cancel()

            with contextlib.suppress(asyncio.CancelledError):
                await task

    async def shutdown(app):
        for socket in list(connections.values()):
            await socket.close(code=1001)

    app.router.add_get("/", websocket)
    app.cleanup_ctx.append(running)
    app.on_shutdown.append(shutdown)

    return app


if __name__ == "__main__":
    web.run_app(
        create_app(),
        host=HOST,
        port=PORT,
        access_log=None,
        print=lambda message: print(message.splitlines()[0].strip("= ")),
    )
