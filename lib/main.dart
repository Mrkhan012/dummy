import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const SnakeGameApp());

class SnakeGameApp extends StatelessWidget {
  const SnakeGameApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snake Game',
      theme: ThemeData(useMaterial3: true),
      home: const SnakeGame(),
      debugShowCheckedModeBanner: false,
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

class _SnakeGameState extends State<SnakeGame> {
  static const int rowCount = 20, colCount = 20;
  static const int totalCells = rowCount * colCount;
  final random = Random();

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

  // settings & persistence
  int highScore = 0;
  Difficulty difficulty = Difficulty.medium;
  final AudioPlayer _audioPlayer = AudioPlayer(); // for short effects
  Duration tickDuration = const Duration(milliseconds: 140);

  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    timer?.cancel();
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
      // regenerate obstacles only if enabled
      if (obstaclesEnabled) _generateObstacles();
    });
    timer?.cancel();
    timer = Timer.periodic(tickDuration, (timer) {
      updateSnake();
    });
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
    final numObs = 20; // tweakable
    while (obstacles.length < numObs) {
      final pos = random.nextInt(totalCells);
      if (!snake.contains(pos) && pos != food) obstacles.add(pos);
    }
  }

  void endGame() {
    timer?.cancel();
    // play die sound (ignore errors)
    _playLocalSound('assets/sounds/die.wav');
    setState(() => isPlaying = false);

    // update high score
    if (score > highScore) {
      highScore = score;
      _savePrefs();
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Center(child: Text('Game Over', style: TextStyle(fontWeight: FontWeight.bold))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Score: $score', style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text('High Score: $highScore', style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    startGame();
                  },
                  icon: const Icon(Icons.replay),
                  label: const Text('Restart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _playLocalSound(String assetPath) async {
    try {
      await _audioPlayer.play(AssetSource(assetPath.replaceFirst('assets/', ''))); 
      // Note: audioplayers's AssetSource expects path inside assets/ when configured.
      // Some versions accept AssetSource('sounds/bite.wav') if declared as assets/sounds/...
    } catch (e) {
      // ignore
    }
  }

  void changeDirection(Direction d) {
    if (!isPlaying) return;
    // Prevent reversing
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

      // wall collision
      if (x < 0 || x >= colCount || y < 0 || y >= rowCount) {
        endGame();
        return;
      }

      // obstacle collision
      if (obstacles.contains(newHead)) {
        endGame();
        return;
      }

      // self collision
      if (snake.contains(newHead)) {
        endGame();
        return;
      }

      snake.add(newHead);

      // ate food
      if (newHead == food) {
        score += 1;
        // play bite sound
        _playLocalSound('assets/sounds/bite.mp3');
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

  Widget getGridCell(int index, double gap) {
    final bool isBody = snake.contains(index);
    final bool isHead = isBody && index == snake.last;
    final bool isFood = index == food;
    final bool isObstacle = obstacles.contains(index);

    if (isFood) {
      return Container(
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Colors.orange, Colors.red]),
          boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.45), blurRadius: 8, spreadRadius: 1)],
        ),
      );
    }

    if (isObstacle) {
      return Container(
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4)],
        ),
      );
    }

    if (isBody) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        margin: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          gradient: isHead
              ? const LinearGradient(colors: [Color(0xFF64FFDA), Color(0xFF00C853)])
              : const LinearGradient(colors: [Color(0xFFB9F6CA), Color(0xFF69F0AE)]),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 3))],
        ),
      );
    }

    // empty cell
    return Container(
      margin: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withOpacity(0.12), width: 0.5),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.globalPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) _dragStart = details.globalPosition - details.delta;
    final current = details.globalPosition;
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

  // UI: difficulty dialog
  Future<void> _showDifficultyDialog() async {
    final result = await showModalBottomSheet<Difficulty>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Choose Difficulty', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Easy'),
              leading: Radio<Difficulty>(value: Difficulty.easy, groupValue: difficulty, onChanged: (v) => Navigator.of(context).pop(v)),
            ),
            ListTile(
              title: const Text('Medium'),
              leading: Radio<Difficulty>(value: Difficulty.medium, groupValue: difficulty, onChanged: (v) => Navigator.of(context).pop(v)),
            ),
            ListTile(
              title: const Text('Hard'),
              leading: Radio<Difficulty>(value: Difficulty.hard, groupValue: difficulty, onChanged: (v) => Navigator.of(context).pop(v)),
            ),
          ]),
        );
      },
    );
    if (result != null) {
      setState(() {
        difficulty = result;
        tickDuration = _durationForDifficulty(difficulty);
        if (isPlaying) {
          // restart timer with new speed
          timer?.cancel();
          timer = Timer.periodic(tickDuration, (t) => updateSnake());
        }
      });
      _savePrefs();
    }
  }

  // toggle obstacles
  void _toggleObstacles() {
    setState(() {
      obstaclesEnabled = !obstaclesEnabled;
      if (obstaclesEnabled) {
        _generateObstacles();
      } else {
        obstacles.clear();
      }
      _savePrefs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFe0f7fa), Color(0xFFe8f5e9)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final screenW = constraints.maxWidth;
            final screenH = constraints.maxHeight;
            final topReserved = max(88.0, screenH * 0.10);
            final availableHeight = screenH - topReserved - 24;
            final boardSize = min(screenW - 24, availableHeight);
            final rawCellSize = boardSize / colCount;
            final gap = max(1.0, rawCellSize * 0.06);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                        ),
                        child: Row(children: [
                          const Icon(Icons.emoji_events, color: Color(0xFF16A085)),
                          const SizedBox(width: 8),
                          Text('Score: $score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('High: $highScore', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                            Text(_difficultyLabel(), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ])
                        ]),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(children: [
                      ElevatedButton(
                        onPressed: () {
                          if (isPlaying) pauseGame();
                          else startGame();
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: isPlaying ? Colors.orangeAccent : Colors.deepPurpleAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(children: [Icon(isPlaying ? Icons.pause : Icons.play_arrow), const SizedBox(width: 6), Text(isPlaying ? 'Pause' : 'Play')]),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: _showDifficultyDialog,
                        icon: const Icon(Icons.speed),
                        tooltip: 'Difficulty',
                      ),
                    ])
                  ]),
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      child: Container(
                        width: boardSize,
                        height: boardSize,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.95), Colors.white.withOpacity(0.9)]),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 8))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: totalCells,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: colCount, childAspectRatio: 1),
                            itemBuilder: (context, idx) => getGridCell(idx, gap),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
                        child: Text('Swipe anywhere to change direction. Eat food, avoid walls & obstacles.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(children: [
                      Row(children: [
                        const Text('Obstacles', style: TextStyle(fontSize: 12)),
                        Switch(value: obstaclesEnabled, onChanged: (_) => _toggleObstacles()),
                      ]),
                      const SizedBox(height: 6),
                      OutlinedButton(onPressed: () { setState(() { score = 0; highScore = 0; _savePrefs(); }); }, child: const Text('Reset High'))
                    ])
                  ]),
                )
              ],
            );
          }),
        ),
      ),
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
