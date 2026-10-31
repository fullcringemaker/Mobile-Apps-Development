import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

const dataUrl = 'http://pstgu.yss.su/iu9/mobiledev/lab4_yandex_map/2023.php?x=var12';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
    const MyApp({super.key});

    @override
    Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Зоомагазины - вариант 13',
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        home: const MapPage(),
    );
}

class Place {
    const Place({
        required this.name,
        required this.address,
        required this.phone,
        required this.point,
    });

    final String name;
    final String address;
    final String phone;
    final Point point;

    factory Place.fromJson(Map<String, dynamic> json) {
        final gps = (json['gps'] as String).split(',');
        final latitude = double.parse(gps[0].trim());
        final longitude = double.parse(gps[1].trim());
        return Place(
            name: json['name'] as String,
            address: json['address'] as String,
            phone: json['tel'] as String,
            point: Point(latitude: latitude, longitude: longitude),
        );
    }
}

class MapPage extends StatefulWidget {
    const MapPage({super.key});

    @override
    State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
    List<Place> _places = [];
    List<MapObject> _markers = [];
    bool _loading = true;
    String? _error;

    @override
    void initState() {
        super.initState();
        _loadPlaces();
    }

    Future<void> _loadPlaces() async {
        setState(() {
            _loading = true;
            _error = null;
        });
        final client = HttpClient();
        try {
            final body = await (() async {
                final request = await client.getUrl(Uri.parse(dataUrl));
                final response = await request.close();
                if (response.statusCode != HttpStatus.ok) {
                    throw HttpException('HTTP ${response.statusCode}');
                }
                return response.transform(utf8.decoder).join();
            })().timeout(const Duration(seconds: 20));

            final json = jsonDecode(body) as List<dynamic>;
            final places = json
                    .map((item) => Place.fromJson(item as Map<String, dynamic>))
                    .toList();
            final icon = BitmapDescriptor.fromAssetImage('assets/marker.png');
            if (!mounted) return;
            setState(() {
                _places = places;
                _markers = [
                    for (var i = 0; i < places.length; i++)
                        PlacemarkMapObject(
                            mapId: MapObjectId('place_$i'),
                            point: places[i].point,
                            opacity: 1,
                            consumeTapEvents: true,
                            icon: PlacemarkIcon.single(
                                PlacemarkIconStyle(
                                    image: icon,
                                    anchor: const Offset(0.49, 0.94),
                                    scale: 0.04,
                                ),
                            ),
                            onTap: (_, _) => _showDetails(places[i]),
                        ),
                ];
                _loading = false;
            });
        } catch (_) {
            if (!mounted) return;
            setState(() {
                _loading = false;
                _error = 'Ошибка загрузки';
            });
        } finally {
            client.close(force: true);
        }
    }

    Future<void> _showAllPlaces(YandexMapController controller) async {
        var south = _places.first.point.latitude;
        var north = south;
        var west = _places.first.point.longitude;
        var east = west;
        for (final place in _places) {
            south = math.min(south, place.point.latitude);
            north = math.max(north, place.point.latitude);
            west = math.min(west, place.point.longitude);
            east = math.max(east, place.point.longitude);
        }
        final latitudePadding = math.max((north - south) * 0.2, 0.002);
        final longitudePadding = math.max((east - west) * 0.2, 0.002);
        await controller.moveCamera(
            CameraUpdate.newGeometry(
                Geometry.fromBoundingBox(
                    BoundingBox(
                        southWest: Point(
                            latitude: south - latitudePadding,
                            longitude: west - longitudePadding,
                        ),
                        northEast: Point(
                            latitude: north + latitudePadding,
                            longitude: east + longitudePadding,
                        ),
                    ),
                ),
            ),
        );
    }

    void _showDetails(Place place) {
        showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                alignment: Alignment.center,
                scrollable: true,
                title: Text(place.name),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        SelectableText('Адрес: ${place.address}'),
                        const SizedBox(height: 12),
                        SelectableText('Телефон: ${place.phone}'),
                        const SizedBox(height: 12),
                        SelectableText('Координаты: ${place.point.latitude}, ${place.point.longitude}'),
                    ],
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Закрыть'),
                    ),
                ],
            ),
        );
    }

    @override
    Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Зоомагазины - Вариант 13')),
        body: SafeArea(
            child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        Text(_error!, textAlign: TextAlign.center),
                                        const SizedBox(height: 16),
                                        ElevatedButton(
                                            onPressed: _loadPlaces,
                                            child: const Text('Повторить'),
                                        ),
                                    ],
                                ),
                            ),
                        )
                    : _places.isEmpty
                    ? const Center(child: Text('Нет объектов'))
                    : YandexMap(mapObjects: _markers, onMapCreated: _showAllPlaces),
        ),
    );
}
