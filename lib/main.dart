import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const SnakeGameApp());

class SnakeGameApp extends StatelessWidget {
  const SnakeGameApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snake Modern',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const SnakeGame(),
    );
  }
}

enum Direction { up, down, left, right }
enum Difficulty { easy, medium, hard }

class SnakeGame extends StatefulWidget {
  const SnakeGame({super.key});
  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> with SingleTickerProviderStateMixin {
  // grid
  static const int rowCount = 20, colCount = 20;
  static const int totalCells = rowCount * colCount;
  final Random random = Random();

  // game state
  List<int> snake = [45, 65, 85];
  int food = 105;
  Direction direction = Direction.down;
  Timer? timer;
  bool isPlaying = false;
  int score = 0;

  // obstacles
  bool obstaclesEnabled = false;
  Set<int> obstacles = {};

  // persistence & audio
  int highScore = 0;
  Difficulty difficulty = Difficulty.medium;
  Duration tickDuration = const Duration(milliseconds: 140);
  final AudioPlayer _audioPlayer = AudioPlayer();

  // gestures
  Offset? _dragStart;

  // UI anim
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    timer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      highScore = prefs.getInt('highScore') ?? 0;
      final diffIndex = prefs.getInt('difficulty') ?? 1;
      difficulty = Difficulty.values[diffIndex.clamp(0, Difficulty.values.length - 1)];
      tickDuration = _durationForDifficulty(difficulty);
      obstaclesEnabled = prefs.getBool('obstacles') ?? false;
      if (obstaclesEnabled) _generateObstacles();
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('highScore', highScore);
    await prefs.setInt('difficulty', difficulty.index);
    await prefs.setBool('obstacles', obstaclesEnabled);
  }

  Duration _durationForDifficulty(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return const Duration(milliseconds: 180);
      case Difficulty.medium:
        return const Duration(milliseconds: 140);
      case Difficulty.hard:
        return const Duration(milliseconds: 100);
    }
  }

  void startGame() {
    setState(() {
      snake = [45, 65, 85];
      direction = Direction.down;
      food = randomFood();
      score = 0;
      isPlaying = true;
      if (obstaclesEnabled) _generateObstacles();
    });
    timer?.cancel();
    timer = Timer.periodic(tickDuration, (_) => updateSnake());
  }

  void pauseGame() {
    timer?.cancel();
    setState(() => isPlaying = false);
  }

  int randomFood() {
    final occupied = {...snake, ...obstacles};
    int pos;
    do {
      pos = random.nextInt(totalCells);
    } while (occupied.contains(pos));
    return pos;
  }

  void _generateObstacles() {
    obstacles.clear();
    final numObs = 18;
    while (obstacles.length < numObs) {
      final pos = random.nextInt(totalCells);
      if (!snake.contains(pos) && pos != food) obstacles.add(pos);
    }
  }

  void changeDirection(Direction d) {
    if (!isPlaying) return;
    if (direction == Direction.left && d == Direction.right) return;
    if (direction == Direction.right && d == Direction.left) return;
    if (direction == Direction.up && d == Direction.down) return;
    if (direction == Direction.down && d == Direction.up) return;
    setState(() => direction = d);
  }

  void updateSnake() {
    setState(() {
      final newHead = calcNewHead();
      final x = newHead % colCount, y = newHead ~/ colCount;

      // wall or obstacle or self collision => game over
      if (x < 0 || x >= colCount || y < 0 || y >= rowCount || obstacles.contains(newHead) || snake.contains(newHead)) {
        _playSound('sounds/die.wav');
        endGame();
        return;
      }

      snake.add(newHead);
      if (newHead == food) {
        score++;
        _playSound('sounds/bite.mp3');
        food = randomFood();
      } else {
        snake.removeAt(0);
      }
    });
  }

  int calcNewHead() {
    final head = snake.last;
    switch (direction) {
      case Direction.right:
        return head + 1;
      case Direction.left:
        return head - 1;
      case Direction.up:
        return head - colCount;
      case Direction.down:
        return head + colCount;
    }
  }

  void endGame() {
    timer?.cancel();
    setState(() => isPlaying = false);
    if (score > highScore) {
      highScore = score;
      _savePrefs();
    }
    Future.delayed(const Duration(milliseconds: 100), () => _showGameOverDialog());
  }

  Future<void> _playSound(String assetPath) async {
    try {
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (_) {
      // ignore sound errors
    }
  }

  // Gesture handlers
  void _onPanStart(DragStartDetails d) => _dragStart = d.globalPosition;

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStart == null) _dragStart = d.globalPosition - d.delta;
    final current = d.globalPosition;
    final dx = current.dx - _dragStart!.dx;
    final dy = current.dy - _dragStart!.dy;
    final absDx = dx.abs(), absDy = dy.abs();
    const threshold = 8.0;
    if (absDx < threshold && absDy < threshold) return;
    if (absDx > absDy) {
      if (dx > 0) changeDirection(Direction.right);
      else changeDirection(Direction.left);
    } else {
      if (dy > 0) changeDirection(Direction.down);
      else changeDirection(Direction.up);
    }
    _dragStart = current;
  }

  // UI Dialogs & utilities
  Future<void> _showGameOverDialog() async {
    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Game Over', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Score: $score', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 4),
                Text('High: $highScore', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      startGame();
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Restart'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ])
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDifficultySheet() async {
    final result = await showModalBottomSheet<Difficulty>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Choose Difficulty', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RadioListTile<Difficulty>(
              title: const Text('Easy'),
              value: Difficulty.easy,
              groupValue: difficulty,
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<Difficulty>(
              title: const Text('Medium'),
              value: Difficulty.medium,
              groupValue: difficulty,
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<Difficulty>(
              title: const Text('Hard'),
              value: Difficulty.hard,
              groupValue: difficulty,
              onChanged: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );

    if (result != null) {
      setState(() {
        difficulty = result;
        tickDuration = _durationForDifficulty(difficulty);
        if (isPlaying) {
          timer?.cancel();
          timer = Timer.periodic(tickDuration, (_) => updateSnake());
        }
      });
      _savePrefs();
    }
  }

  void _toggleObstacles() {
    setState(() {
      obstaclesEnabled = !obstaclesEnabled;
      if (obstaclesEnabled) _generateObstacles();
      else obstacles.clear();
      _savePrefs();
    });
  }

  // UI building
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // immersive modern background
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFFe6f7ff), const Color(0xFFeef9f1)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final screenW = constraints.maxWidth;
            final screenH = constraints.maxHeight;
            final topReserved = max(92.0, screenH * 0.10);
            final availableHeight = screenH - topReserved - 28;
            final boardSize = min(screenW - 32, availableHeight);
            final rawCellSize = boardSize / colCount;
            final gap = max(1.0, rawCellSize * 0.06);

            return Column(children: [
              // top bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.emoji_events, color: Color(0xFF0E9F8B)),
                          ),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Score', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text('$score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          ]),
                          const Spacer(),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(children: [
                              const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
                              const SizedBox(width: 6),
                              Text('$highScore', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 4),
                            Text(_difficultyLabel(), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ])
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Animated Play/Pause floating button
                  ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPlaying ? Colors.orangeAccent : Colors.deepPurpleAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 8,
                      ),
                      onPressed: () {
                        if (isPlaying) pauseGame();
                        else startGame();
                      },
                      child: Row(children: [Icon(isPlaying ? Icons.pause : Icons.play_arrow), const SizedBox(width: 6), Text(isPlaying ? 'Pause' : 'Play')]),
                    ),
                  ),
                ]),
              ),

              // board
              Expanded(
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    child: Container(
                      width: boardSize,
                      height: boardSize,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(colors: [Colors.white.withOpacity(0.95), Colors.white.withOpacity(0.88)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 10))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: totalCells,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: colCount, childAspectRatio: 1),
                          itemBuilder: (context, index) => _buildCell(index, gap),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // bottom controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.swipe, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Swipe anywhere to change direction • Avoid walls & obstacles', style: TextStyle(fontSize: 13))),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(children: [
                    Row(children: [
                      const Text('Obstacles', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.95,
                        child: Switch(
                          value: obstaclesEnabled,
                          onChanged: (_) => _toggleObstacles(),
                          activeColor: const Color(0xFF0E9F8B),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      IconButton(onPressed: _showDifficultySheet, icon: const Icon(Icons.speed)),
                      OutlinedButton(onPressed: () { setState(() { score = 0; highScore = 0; _savePrefs(); }); }, child: const Text('Reset High')),
                    ])
                  ])
                ]),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _buildCell(int index, double gap) {
    final bool isBody = snake.contains(index);
    final bool isHead = isBody && index == snake.last;
    final bool isFood = index == food;
    final bool isObs = obstacles.contains(index);

    if (isFood) {
      return Container(
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Colors.orange.shade300, Colors.red.shade700]),
          boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.42), blurRadius: 8, spreadRadius: 1)],
        ),
      );
    }

    if (isObs) {
      return Container(
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 4)],
        ),
      );
    }

    if (isBody) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          gradient: isHead
              ? const LinearGradient(colors: [Color(0xFF64FFDA), Color(0xFF00C853)])
              : const LinearGradient(colors: [Color(0xFFB9F6CA), Color(0xFF69F0AE)]),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 6, offset: const Offset(0, 3))],
        ),
      );
    }

    // empty tile — soft rounded tile
    return Container(
      margin: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withOpacity(0.10), width: 0.4),
      ),
      child: const SizedBox.shrink(),
    );
  }

  String _difficultyLabel() {
    switch (difficulty) {
      case Difficulty.easy:
        return 'Easy';
      case Difficulty.medium:
        return 'Medium';
      case Difficulty.hard:
        return 'Hard';
    }
  }
}

/// Simple reusable glassmorphism card used across UI
class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.45)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 6))],
          ),
          child: child,
        ),
      ),
    );
  }
}
