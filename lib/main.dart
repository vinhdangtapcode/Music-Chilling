import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Music App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Music Chilling'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> _playlist = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isAutoReplay = false;
  Directory? _musicDir;
  File? _manifestFile;

  @override
  void initState() {
    super.initState();
    _initMusicDir();
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
      if (state.processingState == ProcessingState.completed) {
        if (_playlist.isNotEmpty) {
          if (_isAutoReplay) {
            // Lặp lại bài hiện tại
            _audioPlayer.seek(Duration.zero);
            _audioPlayer.play();
          } else {
            // Phát bài tiếp theo
            _playNext();
          }
        }
      }
    });
  }

  Future<void> _initMusicDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${dir.path}/music');
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
      // Copy các file nhạc mẫu từ assets sang documents/music
      await _copyAssetsToMusicDir(musicDir);
    }
    _musicDir = musicDir;
    _manifestFile = File('${musicDir.path}/manifest.txt');
    if (!await _manifestFile!.exists()) {
      await _manifestFile!.writeAsString('');
    }
    await _loadMusicFromDocuments();
  }

  Future<void> _copyAssetsToMusicDir(Directory musicDir) async {
    // Chỉ copy manifest.txt và các file mp3 mẫu nếu cần
    final context = this.context;
    final manifestContent = await DefaultAssetBundle.of(context).loadString('assets/music/manifest.txt');
    final assetSongs = manifestContent
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final song in assetSongs) {
      final bytes = await DefaultAssetBundle.of(context).load('assets/music/$song');
      final file = File('${musicDir.path}/$song');
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    await File('${musicDir.path}/manifest.txt').writeAsString(assetSongs.join('\n'));
  }

  Future<void> _loadMusicFromDocuments() async {
    if (_manifestFile == null) return;
    final manifestContent = await _manifestFile!.readAsString();
    final docSongs = manifestContent
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => '${_musicDir!.path}/$e')
        .toList();
    setState(() {
      _playlist = docSongs;
      _currentIndex = 0;
    });
    if (docSongs.isNotEmpty) {
      await _audioPlayer.setFilePath(docSongs[0]);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudio(int index) async {
    if (_playlist.isEmpty) return;
    await _audioPlayer.setFilePath(_playlist[index]);
    await _audioPlayer.play();
    setState(() {
      _currentIndex = index;
      _isPlaying = true;
    });
  }

  Future<void> _togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      if (_audioPlayer.playerState.processingState == ProcessingState.completed) {
        // Nếu đã phát hết bài, phát lại từ đầu
        await _audioPlayer.seek(Duration.zero);
      }
      await _audioPlayer.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  Future<void> _playNext() async {
    if (_playlist.isEmpty) return;
    int nextIndex = (_currentIndex + 1) % _playlist.length;
    await _playAudio(nextIndex);
  }

  Future<void> _playPrevious() async {
    if (_playlist.isEmpty) return;
    int prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    await _playAudio(prevIndex);
  }

  void _shufflePlaylist() {
    if (_playlist.isEmpty) return;
    setState(() {
      _playlist.shuffle();
      _currentIndex = 0;
    });
    if (_playlist.isNotEmpty) {
      _audioPlayer.setFilePath(_playlist[0]);
    }
  }

  // Helper to parse song name and artist from file name
  Map<String, String> _parseSongInfo(String filePath) {
    final fileName = filePath.split('/').last;
    final nameParts = fileName.replaceAll('.mp3', '').split(' - ');
    String song = nameParts.isNotEmpty ? nameParts[0] : 'Unknown';
    String artist = nameParts.length > 1 ? nameParts[1] : 'Unknown Artist';
    return {'song': song, 'artist': artist};
  }

  // Hàm tìm kiếm bài hát theo tên (không phân biệt hoa thường, bỏ dấu)
  List<int> _searchSongIndexes(String query) {
    String normalize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll(RegExp(r'[đ]'), 'd');
    final normQuery = normalize(query);
    return List.generate(_playlist.length, (i) {
      final info = _parseSongInfo(_playlist[i]);
      final songNorm = normalize(info['song'] ?? '');
      if (songNorm.contains(normQuery)) return i;
      return -1;
    }).where((i) => i != -1).toList();
  }

  void _showSearchDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        List<int> searchResults = [];
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF232323),
              title: const Text('Tìm kiếm bài hát', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Nhập tên bài hát...',
                        hintStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.greenAccent),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchResults = _searchSongIndexes(value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (controller.text.isNotEmpty)
                      ...searchResults.isEmpty
                          ? [const Text('Không tìm thấy bài hát phù hợp.', style: TextStyle(color: Colors.white70))]
                          : searchResults.map((i) {
                              final info = _parseSongInfo(_playlist[i]);
                              return ListTile(
                                title: Text(info['song'] ?? '', style: const TextStyle(color: Colors.white)),
                                subtitle: Text(info['artist'] ?? '', style: const TextStyle(color: Colors.white54)),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _playAudio(i);
                                },
                              );
                            }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng', style: TextStyle(color: Colors.greenAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addSongFromLocal() async {
    // Xin quyền truy cập bộ nhớ
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      bool? accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF232323),
          title: const Text('Cấp quyền truy cập bộ nhớ', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Ứng dụng cần quyền truy cập bộ nhớ để thêm bài hát từ thiết bị của bạn.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Đồng ý', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      status = await Permission.storage.request();
      if (!status.isGranted) {
        // Nếu người dùng từ chối, không thông báo nữa, chỉ return
        return;
      }
    }
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3']);
    if (result != null && result.files.single.path != null) {
      String? filePath = result.files.single.path;
      final nameController = TextEditingController();
      final artistController = TextEditingController();
      bool valid = false;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF232323),
            title: const Text('Nhập thông tin bài hát', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tên bài hát',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: artistController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tên tác giả',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty && artistController.text.trim().isNotEmpty) {
                    valid = true;
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Thêm', style: TextStyle(color: Colors.greenAccent)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      );
      if (valid && filePath != null && _musicDir != null && _manifestFile != null) {
        String newName = "${nameController.text.trim()} - ${artistController.text.trim()}.mp3";
        String destPath = "${_musicDir!.path}/$newName";
        try {
          await File(filePath).copy(destPath);
        } catch (e) {}
        List<String> lines = await _manifestFile!.readAsLines();
        if (!lines.contains(newName)) {
          lines.add(newName);
          await _manifestFile!.writeAsString(lines.join('\n'));
        }
        await _loadMusicFromDocuments();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181818),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.music_note, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.title, style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _showSearchDialog,
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: _addSongFromLocal,
              tooltip: 'Thêm bài hát',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          // Album art and song info
          if (_playlist.isNotEmpty)
            Column(
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.music_note, size: 120, color: Colors.white38),
                ),
                const SizedBox(height: 24),
                Builder(
                  builder: (context) {
                    final info = _parseSongInfo(_playlist[_currentIndex]);
                    return Column(
                      children: [
                        Text(
                          info['song']!,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          info['artist']!,
                          style: const TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          const SizedBox(height: 32),
          // Playlist
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF232323),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: _playlist.isEmpty
                  ? const Center(child: Text('Không tìm thấy bài hát.', style: TextStyle(color: Colors.white54)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      itemCount: _playlist.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final filePath = _playlist[index];
                        final info = _parseSongInfo(filePath);
                        return ListTile(
                          leading: Icon(
                            index == _currentIndex ? Icons.play_arrow : Icons.music_note,
                            color: index == _currentIndex ? Colors.greenAccent : Colors.white54,
                          ),
                          title: Text(
                            info['song']!,
                            style: TextStyle(
                              color: index == _currentIndex ? Colors.greenAccent : Colors.white,
                              fontWeight: index == _currentIndex ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            info['artist']!,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          onTap: () => _playAudio(index),
                          selected: index == _currentIndex,
                          selectedTileColor: Colors.greenAccent.withOpacity(0.00),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        );
                      },
                    ),
            ),
          ),
          // Player controls
          if (_playlist.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: IconButton(
                      icon: Icon(_isAutoReplay ? Icons.repeat_one : Icons.repeat, size: 32, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isAutoReplay = !_isAutoReplay;
                        });
                      },
                      tooltip: _isAutoReplay ? 'Lặp lại 1 bài' : 'Tự động phát tiếp',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                      onPressed: _playPrevious,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent,
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40, color: Colors.black),
                        onPressed: _togglePlayPause,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                      onPressed: _playNext,
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.shuffle, size: 32, color: Colors.white),
                      onPressed: _shufflePlaylist,
                      tooltip: 'Tráo ngẫu nhiên',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
