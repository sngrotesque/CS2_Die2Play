import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(
      AppConstants.windowWidthDefault,
      AppConstants.windowHeightDefault,
    ),
    minimumSize: Size(
      AppConstants.windowWidthDefault,
      AppConstants.windowHeightDefault,
    ),
    maximumSize: Size(
      AppConstants.windowWidthMax,
      AppConstants.windowHeightMax,
    ),
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
    await windowManager.setTitle(
      'CS2. Die to play',
    ); // 不去更改 windows\runner\main.cpp 文件。
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          surfaceTint: Colors.transparent,
        ),
        fontFamily: 'simhei', // 黑体
        fontFamilyFallback: const [
          'Microsoft YaHei', // 微软雅黑
          'sans-serif', // 无衬线字体
        ],
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final addressController = TextEditingController(text: '127.0.0.1');
  final portController = TextEditingController(text: '23331');
  final outputController = TextEditingController();
  final urlController = TextEditingController(
    text: 'https://www.douyin.com/?recommend=1',
  );

  final Color outputControlTextColor = const Color.fromRGBO(59, 211, 137, 1);
  final String configFilename = 'gamestate_integration_cs2_die2play.cfg';

  HttpServer? _server;
  bool _isServerRunning = false;
  bool _playerIsDead = false;

  // 壁纸状态：null 表示使用第一张默认壁纸，非空字符串分两种：
  // 以 "asset:" 开头表示内置资源路径，否则为本地文件路径
  String? _currentWallpaper;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  void _log(String message) {
    final timeStamp = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      outputController.text += '${timeStamp ~/ 1000} $message\n';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _playClickSound(String assetPath) async {
    try {
      // await _audioPlayer.stop(); // 先停止之前可能正在播放的音效
      await _audioPlayer.play(AssetSource(assetPath)); // 播放新音效
    } catch (e) {
      _log('播放音效失败: $e');
    }
  }

  // 将CS2拉回前台
  Future<void> _forusCS2Window() async {
    try {
      await Process.run('powershell', [
        '-Command',
        r'(New-Object -ComObject WScript.Shell).AppActivate((Get-Process -Name "cs2").Id)',
      ]);
      _log('已将 CS2 窗口置顶');
    } catch (e) {
      _log('拉回 CS2 失败: $e');
    }
  }

  // 获取所有内置壁纸的资源路径
  List<String> _getBuiltinWallpapers() => List.generate(
    15,
    (i) => 'assets/background/bg_${i.toString().padLeft(2, '0')}.jpg',
  );

  String get _defaultWallpaper => _getBuiltinWallpapers()[5]; // bg_05.jpg

  // 从文件选择壁纸
  Future<void> _changeWallpaperFromFile() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.single.path;
      if (filePath != null) {
        setState(() {
          _currentWallpaper = filePath; // 文件路径不带前缀
        });
        _log('壁纸已更换：$filePath');
      }
    }
  }

  // 弹出默认壁纸选择对话框
  Future<void> _showDefaultWallpaperPicker() async {
    final wallpapers = _getBuiltinWallpapers();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择默认壁纸'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: wallpapers.length,
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () => Navigator.pop(ctx, wallpapers[index]),
                child: Image.asset(
                  wallpapers[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _currentWallpaper = 'asset:$selected'; // 标记为内置资源
      });
      _log('壁纸已更换：内置 #${wallpapers.indexOf(selected) + 1}');
    }
  }

  // 保存当前壁纸到指定路径
  Future<void> _saveCurrentWallpaper() async {
    final saveDir = await FilePicker.getDirectoryPath();
    if (saveDir == null) return;

    try {
      File sourceFile;
      String fileName;

      if (_currentWallpaper == null ||
          _currentWallpaper!.startsWith('asset:')) {
        // 当前为内置壁纸，需要先提取资源并保存
        final assetPath = _currentWallpaper != null
            ? _currentWallpaper!.substring(6) // 去掉 "asset:" 前缀
            : _defaultWallpaper;
        final bytes = await _loadAssetBytes(assetPath);
        fileName = assetPath.split('/').last;
        sourceFile = File('$saveDir/$fileName');
        await sourceFile.writeAsBytes(bytes);
      } else {
        // 当前为用户自定义文件，直接复制
        sourceFile = File(_currentWallpaper!);
        fileName = sourceFile.uri.pathSegments.last;
        final destFile = File('$saveDir/$fileName');
        await sourceFile.copy(destFile.path);
      }

      _log('壁纸已保存到：$saveDir/$fileName');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('壁纸已保存：$saveDir/$fileName')));
      }
    } catch (e) {
      _log('保存壁纸失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  // 从 assets 读取文件字节
  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final bundle = DefaultAssetBundle.of(context);
    final byteData = await bundle.load(assetPath);
    return byteData.buffer.asUint8List();
  }

  // 生成实际的 cfg 内容
  String _buildCfgContent() {
    final addr = addressController.text;
    final port = portController.text;
    String cfgContent =
        ('"CS2_Die2Play"\n'
        '{\n'
        '    "uri"               "http://$addr:$port"\n' // 服务器地址和端口
        '    "timeout"           "5.0"\n' // 超时时间，如果服务器超时之前未响应游戏丢弃此请求。
        '    "buffer"            "0.0"\n' // 用于合并短时间内的多次事件，减少请求数量。设置为 0.0 不合并。
        '    "throttle"          "0.5"\n' // 节流阀，最快每{throttle}秒发一次更新。
        '    "heartbeat"         "1.0"\n' // 心跳包每{heartbeat}秒发一次（这个必须要有且必须短）。
        '    "data" {\n' // 数据段（1为真，0为假）
        '        "provider"       "1"\n' // 包含游戏提供者的信息（如SteamId、版本号、时间戳等）。
        '        "map"            "1"\n' // 当前地图信息（如地图名、回合数等）。
        '        "round"          "1"\n' // 当前回合状态（如CT、T）。
        '        "player_id"      "1"\n' // 玩家身份信息（如SteamId、名字），用于判断玩家身份防止看队友的时候也跳转。
        '        "player_state"   "1"\n' // 关键，当前玩家状态（包含生命值、护甲值、金钱等）。
        '    }\n'
        '}\n');
    return cfgContent;
  }

  // 保存配置文件
  Future<void> _saveConfig() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存提示'),
        content: Text(
          '默认路径为：\n'
          '{你的Steam安装目录}\\steamapps\\common\\Counter-Strike Global Offensive\\game\\csgo\\cfg\n\n'
          '由于CS2识别固定文件名，所以将文件名将固定为 $configFilename\n\n'
          '点击“我知道了”开始保存。',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );

    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null) {
      _log('取消保存');
      return;
    }

    try {
      final file = File('$selectedDirectory/$configFilename');
      await file.writeAsString(_buildCfgContent());
      _log('配置文件已保存到: ${file.path}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存成功：${file.path}')));
      }
    } catch (e) {
      _log('保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  // 启动服务器
  Future<void> _startServer() async {
    _playClickSound('sounds/click_01.wav');
    if (_isServerRunning) {
      _log('服务器已在运行中');
      return;
    }

    final addr = addressController.text;
    final port = int.tryParse(portController.text);
    if (port == null) {
      _log('端口号无效');
      return;
    }

    try {
      _server = await HttpServer.bind(addr, port);
      _isServerRunning = true;
      _log('服务器启动: $addr:$port');
      _handleRequests(_server!);
    } catch (e) {
      _log('服务器启动失败: $e');
      _isServerRunning = false;
    }
  }

  // 处理 HTTP 请求
  Future<void> _handleRequests(HttpServer server) async {
    await for (HttpRequest request in server) {
      try {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
          request.response.close();
          continue;
        }

        final body = await utf8.decodeStream(request);
        Map<String, dynamic> data;
        try {
          data = json.decode(body) as Map<String, dynamic>;
          debugPrint('调试：${json.encode(data)}');
        } catch (e) {
          _log('JSON 解析失败: $e');
          request.response.statusCode = 400;
          request.response.close();
          continue;
        }

        if (data['map'] == null) {
          _log('玩家还未进入游戏，正在大厅。');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        if (data['player'] == null) {
          _log('未正式开始游戏，正在过场动画。');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        final String providerId = data['provider']['steamid'] as String;
        final String currentPlayerId = data['player']['steamid'] as String;

        if (providerId != currentPlayerId) {
          _log('当前非玩家本人。');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        final int health = data['player']['state']['health'] as int;
        if (_playerIsDead && (health == 100)) {
          _log('玩家已复活，拉回CS2。');
          _forusCS2Window();
          _playerIsDead = false;
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        if (health == 0) {
          if (_playerIsDead) {
            _log('玩家未复活，跳过。');
          } else {
            _log('玩家被击杀。');
            _playerIsDead = true;
            final targetUrl = urlController.text;
            await Process.run('cmd', ['/c', 'start', ' ', targetUrl]);
          }
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        request.response.statusCode = 200;
        await request.response.close();
      } catch (e) {
        _log('处理请求时出错: $e');
        try {
          request.response.statusCode = 500;
          request.response.close();
        } catch (_) {}
      }
    }
  }

  void _stopServer() {
    _playClickSound('sounds/click_02.wav');
    if (!_isServerRunning) {
      _log('服务器未在运行');
      return;
    }
    _server?.close();
    _server = null;
    _isServerRunning = false;
    _playerIsDead = false;
    _log('服务器已手动停止');
    setState(() {});
  }

  @override
  void dispose() {
    _server?.close();
    addressController.dispose();
    portController.dispose();
    outputController.dispose();
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: false,
      appBar: _buildAppBarView(),
      body: _buildBodyView(),
    );
  }

  PreferredSize _buildAppBarView() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromRGBO(0, 81, 255, 0.502),
              Color.fromRGBO(255, 74, 74, 0.761),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text(
                'CS2 GameStateIntegration 配置',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.image, color: Colors.white),
                tooltip: '壁纸选项',
                onSelected: (value) {
                  switch (value) {
                    case 'builtin':
                      _showDefaultWallpaperPicker();
                      break;
                    case 'file':
                      _changeWallpaperFromFile();
                      break;
                    case 'save':
                      _saveCurrentWallpaper();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'builtin', child: Text('选择默认壁纸')),
                  const PopupMenuItem(value: 'file', child: Text('从文件选择壁纸')),
                  const PopupMenuItem(value: 'save', child: Text('保存当前壁纸')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyView() {
    return Stack(
      children: [
        Positioned.fill(child: _buildWallpaper()),
        Positioned.fill(
          child: Container(color: const Color.fromRGBO(0, 0, 0, 0.5)),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('地址：', style: AppConstants.textStyle()),
                            Expanded(
                              child: TextField(
                                style: AppConstants.textFieldTextStyle(),
                                controller: addressController,
                                decoration: AppConstants.textFieldInputStyle(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('端口：', style: AppConstants.textStyle()),
                            Expanded(
                              child: TextField(
                                style: AppConstants.textFieldTextStyle(),
                                controller: portController,
                                decoration: AppConstants.textFieldInputStyle(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _startServer,
                              style: AppConstants.buttonStyle(Colors.red),
                              child: const Text('启动'),
                            ),
                            const Spacer(flex: 1),
                            ElevatedButton(
                              onPressed: _stopServer,
                              style: AppConstants.buttonStyle(Colors.lightBlue),
                              child: const Text('停止'),
                            ),
                            const Spacer(flex: 9),
                            ElevatedButton(
                              onPressed: () {
                                final gameUrl = Uri.parse(
                                  'steam://rungameid/730',
                                );
                                launchUrl(gameUrl);
                              },
                              style: AppConstants.buttonStyle(Colors.amber),
                              child: const Text('打开游戏'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _saveConfig,
                          style: AppConstants.buttonStyle(
                            Colors.white,
                            backgroundColor: const Color.fromRGBO(
                              79,
                              22,
                              236,
                              0.4,
                            ),
                          ),
                          icon: const Icon(Icons.save),
                          label: const Text('保存 CFG 文件'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '由于使用了GSI功能，所以必须结合CFG文件使用。\n请将CFG保存到你的CS2路径下。',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppConstants.defaultFontColor,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Text('网址：', style: AppConstants.textStyle()),
                            Expanded(
                              child: TextField(
                                style: AppConstants.textFieldTextStyle(),
                                controller: urlController,
                                decoration: AppConstants.textFieldInputStyle(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('信息输出：', style: AppConstants.textStyle()),
                            Spacer(),
                            ElevatedButton(
                              onPressed: () {
                                outputController.text = '目前此功能仅为保留，无实际功能。';
                              },
                              style: AppConstants.buttonStyle(
                                AppConstants.defaultFontColor,
                              ),
                              child: Text('查找CS2路径'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                outputController.text = '';
                              },
                              style: AppConstants.buttonStyle(
                                AppConstants.defaultFontColor,
                              ),
                              child: Text('清空控制台'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: TextField(
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: outputControlTextColor,
                              ),
                              controller: outputController,
                              maxLines: null,
                              expands: true,
                              readOnly: true,
                              scrollController: _scrollController,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color.fromRGBO(0, 0, 0, 0.85),
                                hintText: '这里会打印服务器运行的结果。',
                                hintStyle: TextStyle(
                                  color: outputControlTextColor,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(8),
                              ),
                              textAlignVertical: TextAlignVertical.top,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWallpaper() {
    String? source = _currentWallpaper;

    if (source == null) {
      // 默认第一张内置壁纸
      return Image.asset(
        _defaultWallpaper,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.black),
      );
    }

    if (source.startsWith('asset:')) {
      return Image.asset(
        source.substring(6),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.black),
      );
    }

    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.black),
    );
  }
}
