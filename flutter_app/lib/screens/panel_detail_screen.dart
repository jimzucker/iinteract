import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/panel.dart';

class PanelDetailScreen extends StatefulWidget {
  final Panel panel;
  final String voiceStyle;
  const PanelDetailScreen({super.key, required this.panel, required this.voiceStyle});

  @override
  State<PanelDetailScreen> createState() => _PanelDetailScreenState();
}

class _PanelDetailScreenState extends State<PanelDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _selectedName;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _onTap(Interaction interaction) async {
    setState(() => _selectedName = interaction.name);
    final sound = widget.voiceStyle == 'boy' ? interaction.boySound : interaction.girlSound;
    await _player.stop();
    await _player.play(AssetSource(sound.replaceFirst('assets/', '')));
  }

  @override
  Widget build(BuildContext context) {
    final interactions = widget.panel.interactions;
    return Scaffold(
      backgroundColor: widget.panel.color,
      appBar: AppBar(
        backgroundColor: widget.panel.color,
        title: Text(widget.panel.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GridView.count(
        crossAxisCount: interactions.length <= 3 ? interactions.length : 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: interactions.map((i) => _InteractionCard(
          interaction: i,
          isSelected: _selectedName == i.name,
          onTap: () => _onTap(i),
        )).toList(),
      ),
    );
  }
}

class _InteractionCard extends StatelessWidget {
  final Interaction interaction;
  final bool isSelected;
  final VoidCallback onTap;
  const _InteractionCard({required this.interaction, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.white, width: 4) : null,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: isSelected ? 12 : 4)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(interaction.imagePath, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
