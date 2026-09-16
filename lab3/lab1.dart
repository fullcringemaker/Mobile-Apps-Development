import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  Future<void> _loadCounter() async {
    final response = await http.get(
      Uri.parse(
        'https://iocontrol.ru/api/readData/savecounter/counter',
      ),
    );

    final data = jsonDecode(response.body);

    setState(() {
      _counter = int.parse(data['value'].toString());
    });
  }

  Future<void> _saveCounter() async {
    await http.get(
      Uri.parse(
        'https://iocontrol.ru/api/sendData/savecounter/counter/$_counter',
      ),
    );
  }

  void _changeCounter(double value) {
    setState(() {
      _counter = value.toInt();
    });
  }

  Future<void> _saveSliderValue(double value) async {
    setState(() {
      _counter = value.toInt();
    });

    await _saveCounter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Current value:',
              ),
              const SizedBox(height: 10),
              Text(
                '$_counter',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 30),
              Slider(
                value: _counter.toDouble(),
                min: -1000,
                max: 1000,
                divisions: 2000,
                label: '$_counter',
                onChanged: _changeCounter,
                onChangeEnd: _saveSliderValue,
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('-1000'),
                  Text('1000'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}