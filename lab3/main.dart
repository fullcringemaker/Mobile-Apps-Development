import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'lab1.dart' as lab1;
import 'lab2.dart' as lab2;
import 'lab3.dart' as lab3;

void main() {
  runApp(const LaboratoryApp());
}

class LaboratoryApp extends StatelessWidget {
  const LaboratoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Лабораторные работы',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const LaboratoryMenuPage(),
    );
  }
}

class LaboratoryMenuPage extends StatefulWidget {
  const LaboratoryMenuPage({super.key});

  @override
  State<LaboratoryMenuPage> createState() {
    return _LaboratoryMenuPageState();
  }
}

class _LaboratoryMenuPageState extends State<LaboratoryMenuPage> {
  int selectedLab = 0;

  String getLabNumber() {
    if (selectedLab == 0) {
      return '01';
    }

    if (selectedLab == 1) {
      return '02';
    }

    return '03';
  }

  String getLabTitle() {
    if (selectedLab == 0) {
      return 'Удалённый счётчик';
    }

    if (selectedLab == 1) {
      return 'Робот и IoControl';
    }

    return 'Робот и MySQL';
  }

  String getLabDescription() {
    if (selectedLab == 0) {
      return 'Изменение значения счётчика с помощью '
          'ползунка и сохранение значения в IoControl.';
    }

    if (selectedLab == 1) {
      return 'Управление скоростями колёс и параметрами '
          'робота через HTTP API IoControl.';
    }

    return 'Управление параметрами робота с сохранением '
        'данных в MySQL и просмотром журнала записей.';
  }

  IconData getLabIcon() {
    if (selectedLab == 0) {
      return CupertinoIcons.slider_horizontal_3;
    }

    if (selectedLab == 1) {
      return CupertinoIcons.antenna_radiowaves_left_right;
    }

    return CupertinoIcons.archivebox;
  }

  void openSelectedLab() {
    Widget page;

    if (selectedLab == 0) {
      page = const lab1.MyHomePage(
        title: 'Лабораторная работа №1',
      );
    } else if (selectedLab == 1) {
      page = const lab2.WheelControllerPage();
    } else {
      page = const lab3.WheelControllerPage();
    }

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) {
          return page;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text(
          'Пульт лабораторных',
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(
                height: 15,
              ),

              const Text(
                'МОБИЛЬНАЯ ЛАБОРАТОРИЯ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.systemGrey,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(
                height: 25,
              ),

              CupertinoSlidingSegmentedControl<int>(
                groupValue: selectedLab,
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'ЛР 1',
                    ),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'ЛР 2',
                    ),
                  ),
                  2: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'ЛР 3',
                    ),
                  ),
                },
                onValueChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    selectedLab = value;
                  });
                },
              ),

              const SizedBox(
                height: 30,
              ),

              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white,
                      borderRadius: BorderRadius.circular(
                        24,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(
                            0x22000000,
                          ),
                          blurRadius: 15,
                          offset: Offset(
                            0,
                            5,
                          ),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 85,
                          height: 85,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBlue,
                            borderRadius: BorderRadius.circular(
                              22,
                            ),
                          ),
                          child: Icon(
                            getLabIcon(),
                            size: 42,
                            color: CupertinoColors.white,
                          ),
                        ),

                        const SizedBox(
                          height: 25,
                        ),

                        Text(
                          'ЛАБОРАТОРНАЯ ${getLabNumber()}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.systemGrey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Text(
                          getLabTitle(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 15,
                        ),

                        Text(
                          getLabDescription(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: CupertinoColors.systemGrey,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 25,
              ),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: openSelectedLab,
                  child: const Text(
                    'Запустить лабораторную',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
