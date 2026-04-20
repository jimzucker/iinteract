import 'package:flutter/material.dart';

class Interaction {
  final String name;
  const Interaction(this.name);

  String get imagePath => 'assets/images/$name.jpg';
  String get boySound => 'assets/sounds/boy_$name.mp3';
  String get girlSound => 'assets/sounds/girl_$name.mp3';
}

class Panel {
  final String title;
  final Color color;
  final List<Interaction> interactions;
  const Panel({required this.title, required this.color, required this.interactions});
}

const List<Panel> panels = [
  Panel(
    title: 'I feel',
    color: Color.fromRGBO(87, 192, 255, 1),
    interactions: [Interaction('happy'), Interaction('sad'), Interaction('angry')],
  ),
  Panel(
    title: 'I need',
    color: Color.fromRGBO(255, 255, 83, 1),
    interactions: [Interaction('drink'), Interaction('eat'), Interaction('bathroom'), Interaction('break')],
  ),
  Panel(
    title: 'I want to',
    color: Color.fromRGBO(253, 135, 39, 1),
    interactions: [Interaction('tv'), Interaction('play'), Interaction('book'), Interaction('computer')],
  ),
  Panel(
    title: 'I need help',
    color: Color.fromRGBO(251, 0, 6, 1),
    interactions: [Interaction('headache'), Interaction('stomach'), Interaction('cut')],
  ),
  Panel(
    title: 'Food',
    color: Color.fromRGBO(18, 136, 67, 1),
    interactions: [Interaction('breakfast'), Interaction('lunch'), Interaction('dinner'), Interaction('dessert')],
  ),
  Panel(
    title: 'Drink',
    color: Color.fromRGBO(42, 130, 255, 1),
    interactions: [Interaction('milk'), Interaction('water'), Interaction('juice'), Interaction('soda')],
  ),
  Panel(
    title: 'Snacks',
    color: Color.fromRGBO(88, 197, 84, 1),
    interactions: [Interaction('chips'), Interaction('cookie'), Interaction('pretzel'), Interaction('fruit')],
  ),
];
