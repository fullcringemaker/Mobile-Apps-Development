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
  final PageController pageController = PageController(
    viewportFraction: 0.88,
  );

  int currentPage = 0;

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  String getLabNumber(int index) {
    if (index == 0) {
      return 'Лабораторная работа №1';
    }

    if (index == 1) {
      return 'Лабораторная работа №2';
    }

    return 'Лабораторная работа №3';
  }

  String getLabTitle(int index) {
    if (index == 0) {
      return 'Удалённый счётчик';
    }

    if (index == 1) {
      return 'Робот и IoControl';
    }

    return 'Робот и MySQL';
  }

  void openLab(int index) {
    Widget page;

    if (index == 0) {
      page = const lab1.MyHomePage(
        title: 'Лабораторная работа №1',
      );
    } else if (index == 1) {
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

  Widget buildPageIndicator(int index) {
    double width = 8;
    Color color = CupertinoColors.systemGrey3;

    if (currentPage == index) {
      width = 24;
      color = CupertinoColors.systemBlue;
    }

    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 250,
      ),
      width: width,
      height: 8,
      margin: const EdgeInsets.symmetric(
        horizontal: 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget buildLaboratoryCard(int index) {
    return GestureDetector(
      onTap: () {
        openLab(index);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 30,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E88E5),
              Color(0xFF1565C0),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 20,
              offset: Offset(
                0,
                10,
              ),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 25,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(getLabNumber(index),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                Text(getLabTitle(index),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor:
      CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text(
          'Лабораторные работы',
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: 3,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return buildLaboratoryCard(index);
                },
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildPageIndicator(0),
                buildPageIndicator(1),
                buildPageIndicator(2),
              ],
            ),

            const SizedBox(
              height: 22,
            ),
          ],
        ),
      ),
    );
  }
}
