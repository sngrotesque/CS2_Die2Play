import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:convert';
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
  final urlController = TextEditingController(text: 'https://www.google.com/');

  final Color outputControlTextColor = const Color.fromRGBO(59, 211, 137, 1);

  HttpServer? _server;
  bool _isServerRunning = false;
  bool _playerIsDead = false;

  String? wallpaperPath; // 自定义壁纸路径，null 则使用默认图片

  void _log(String message) {
    setState(() {
      outputController.text += '$message\n';
    });
  }

  // 更换壁纸
  Future<void> _changeWallpaper() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.single.path;
      if (filePath != null) {
        setState(() {
          wallpaperPath = filePath;
        });
        _log('壁纸已更换：$filePath');
      }
    }
  }

  // 生成实际的 cfg 内容
  String _buildCfgContent() {
    final addr = addressController.text;
    final port = portController.text;
    String cfgContent =
        ('"CS2 automatically executed"\n'
        '{\n'
        '  "uri"             "http://$addr:$port"\n'
        '  "timeout"         "5.0"\n'
        '  "buffer"          "0.1"\n'
        '  "throttle"        "0.1"\n'
        '  "heartbeat"       "30.0"\n'
        '  "data"\n'
        '  {\n'
        '    "provider"      "1"\n'
        '    "player_id"     "1"\n'
        '    "player_state"  "1"\n'
        '  }\n'
        '}\n');
    return cfgContent;
  }

  // 保存配置文件
  Future<void> _saveConfig() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存提示'),
        content: const Text(
          '默认路径通常为：\n'
          'SteamLibrary\\steamapps\\common\\Counter-Strike Global Offensive\\game\\csgo\\cfg\n\n'
          '由于CS2识别固定文件名，所以将文件名将固定为 gamestate_integration_cs2.cfg',
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
      final file = File('$selectedDirectory/gamestate_integration_cs2.cfg');
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
        } catch (e) {
          _log('JSON 解析失败: $e');
          request.response.statusCode = 400;
          request.response.close();
          continue;
        }

        if (!data.containsKey('player')) {
          _log('非任何观察视角，比如本回合结束/未开始等');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        final provider = data['provider'] as Map<String, dynamic>?;
        final player = data['player'] as Map<String, dynamic>?;
        if (provider == null || player == null) {
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        if (provider['steamid'] != player['steamid']) {
          _log('不是玩家本人，跳过执行。');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        final state = player['state'] as Map<String, dynamic>?;
        if (state == null) {
          _log('玩家未在对局中，等待进入游戏...');
          request.response.statusCode = 200;
          request.response.close();
          continue;
        }

        final health = state['health'] as int? ?? 100;
        if (health == 0) {
          if (_playerIsDead) {
            _log('玩家已经阵亡，跳过执行。');
          } else {
            _log('执行指定操作（打开链接）。');
            final targetUrl = urlController.text;

            // 确保浏览器窗口可以被置顶
            await Process.run('cmd', ['/c', 'start', ' ', targetUrl]);
            _playerIsDead = true;
          }
        } else {
          _log('玩家未阵亡，重新计算。');
          _playerIsDead = false;
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.text;
        request.response.write('OK');
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

  // 手动停止服务器
  void _stopServer() {
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
              Spacer(),
              IconButton(
                onPressed: _changeWallpaper, // 绑定更换壁纸方法
                tooltip: '更换壁纸',
                icon: const Icon(Icons.image, color: Colors.white),
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
        // 最底层：壁纸
        Positioned.fill(child: _buildWallpaper()),
        // 中层：半透明黑色遮罩
        Positioned.fill(
          child: Container(color: const Color.fromRGBO(0, 0, 0, 0.5)),
        ),
        // 最上层：原有左右布局，留出顶部 AppBar 高度
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(top: 60), // AppBar 高度
            child: Row(
              children: [
                // 左半区域
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 地址
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
                        // 端口
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
                        // 启停按钮
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _startServer,
                              style: AppConstants.buttonStyle(Colors.red),
                              child: const Text('启动'),
                            ),
                            Spacer(),
                            ElevatedButton(
                              onPressed: _stopServer,
                              style: AppConstants.buttonStyle(Colors.lightBlue),
                              child: const Text('停止'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 保存配置文件按钮
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
                          label: const Text('保存配置文件'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '请将文件保存在：\nSteamLibrary\\steamapps\\common\\Counter-Strike Global Offensive\\game\\csgo\\cfg',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppConstants.defaultFontColor,
                          ),
                        ),
                        const Spacer(),
                        // 左下角：自定义网址
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
                // 右半区域
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('信息输出：', style: AppConstants.textStyle()),
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

  // 壁纸构建组件
  Widget _buildWallpaper() {
    if (wallpaperPath != null) {
      return Image.file(
        File(wallpaperPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.black),
      );
    }
    // 默认壁纸，若未提供 assets/default_wallpaper.png 则显示纯黑背景
    return Image.asset(
      'assets/background/bg_05.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.black),
    );
  }
}
