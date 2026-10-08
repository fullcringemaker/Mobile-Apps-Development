import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var indexAngle = 0.0;
  var middleAngle = 0.0;
  var ringAngle = 0.0;
  var pinkyAngle = 0.0;
  final Future<List<Mesh3D>> sphere = _generatePoints();

  final _controller = DiTreDiController(
    rotationX: 0,
    rotationY: 0,
    light: vector.Vector3(-0.5, -0.5, 0.5),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(),
      title: 'DiTreDi Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Flex(
            crossAxisAlignment: CrossAxisAlignment.start,
            direction: Axis.vertical,
            children: [
              FutureBuilder(
                  future: sphere,
                  builder: (BuildContext context, AsyncSnapshot<List<Mesh3D>> snapshot){
                    List<Widget> children;
                    if(snapshot.hasData) {
                      children = <Widget>[
                        Expanded(
                          child: DiTreDiDraggable(
                            controller: _controller,
                            child: DiTreDi(
                              figures: [
                                TransformModifier3D(
                                    snapshot.data![0],
                                    Matrix4.identity()
                                      ..rotateX(-pi/2)
                                ),
                                TransformModifier3D(
                                    snapshot.data![1],
                                    Matrix4.identity()
                                      ..rotateX(-pi/2)
                                      ..translate(3.05,1.15,8.75)
                                      ..translate(-0.2,-0.25, -2.2)
                                      ..rotateX(-(indexAngle * pi/18))
                                      ..translate(0.2,0.25, 2.2)
                                ),
                                TransformModifier3D(
                                    snapshot.data![2],
                                    Matrix4.identity()
                                      ..rotateX(-pi/2)
                                      ..translate(0.7,0.0,9.75)
                                      ..translate(0.0,-0.5, -2.25)
                                      ..rotateX(-(middleAngle * pi/18))
                                      ..translate(0.0,0.5, 2.25)
                                ),
                                TransformModifier3D(
                                    snapshot.data![3],
                                    Matrix4.identity()
                                      ..rotateX(-pi/2)
                                      ..translate(-2.0,-0.56,9.1)
                                      ..translate(0.0,-0.25, -2.2)
                                      ..rotateX(-(ringAngle * pi/18))
                                      ..translate(0.0, 0.25, 2.2)
                                      ..rotate
                                ),
                                TransformModifier3D(
                                    snapshot.data![4],
                                    Matrix4.identity()
                                      ..rotateX(-pi/2)
                                      ..translate(-4.65,-1.0,7.15)
                                      ..translate(0.0,0.0, -1.25)
                                      ..rotateX(-(pinkyAngle * pi/18))
                                      ..translate(0.0,0.0, 1.25)
                                ),
                              ],
                              controller: _controller,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("Drag to rotate. Scroll to zoom"),
                        ),
                        Expanded(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children:[
                                Slider(
                                  value: indexAngle,
                                  min: 0,
                                  max: 12,
                                  divisions: 13,
                                  label: (180 - 10 * indexAngle.round()).toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      indexAngle = value;
                                    });
                                  },
                                ),
                                Slider(
                                  value: middleAngle,
                                  min: 0,
                                  max: 12,
                                  divisions: 13,
                                  label: (180 - 10 * middleAngle.round()).toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      middleAngle = value;
                                    });
                                  },
                                ),
                                Slider(
                                  value: ringAngle,
                                  min: 0,
                                  max: 12,
                                  divisions: 13,
                                  label: (180 - 10 * ringAngle.round()).toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      ringAngle = value;
                                    });
                                  },
                                ),
                                Slider(
                                  value: pinkyAngle,
                                  min: 0,
                                  max: 12,
                                  divisions: 13,
                                  label: (180 - 10 * pinkyAngle.round()).toString(),
                                  onChanged: (double value) {
                                    setState(() {
                                      pinkyAngle = value;
                                    });
                                  },
                                ),
                              ]
                          ),
                        )
                      ];
                    }else{
                      children = <Widget>[
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("Failed to load"),
                        )
                      ];
                    }
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: children,
                      ),
                    );
                  }),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List<Mesh3D>> _generatePoints() async{
  return [
    Mesh3D(await ObjParser().loadFromResources("assets/hand/hand.obj")),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/index.obj"),),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/middle.obj"),),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/ring.obj"),),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/pinky.obj"),)
  ];
}
