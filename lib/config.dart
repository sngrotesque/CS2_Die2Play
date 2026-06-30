import 'package:flutter/material.dart';

class AppConstants {
  // 禁止实例化
  AppConstants._();

  // 窗口大小限制
  static const double windowWidthMin = 960;
  static const double windowHeightMin = 540;
  static const double windowWidthDefault = windowWidthMin;
  static const double windowHeightDefault = windowHeightMin;
  static const double windowWidthMax = 1280;
  static const double windowHeightMax = 768;

  // 默认字体样式
  static const Color defaultFontColor = Color.fromRGBO(243, 255, 255, 1);

  static TextStyle textStyle() {
    return const TextStyle(color: defaultFontColor, fontSize: 24);
  }

  // 输入框文本样式
  static TextStyle textFieldTextStyle() {
    return TextStyle(color: defaultFontColor, fontSize: 20);
  }

  // 输入框样式
  static InputDecoration textFieldInputStyle() {
    return const InputDecoration(
      fillColor: Color(0x30ffffff),
      filled: true,
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }

  // 按钮样式
  static ButtonStyle buttonStyle(
    Color bottonFontColor, {
    Color? backgroundColor,
    Color? outlineColor,
  }) {
    return ElevatedButton.styleFrom(
      foregroundColor: bottonFontColor, // 文字颜色
      backgroundColor: backgroundColor ?? Colors.transparent, // 背景色
      disabledForegroundColor: Colors.grey, // 禁用时文字颜色
      disabledBackgroundColor: Colors.grey.shade300,
      // shadowColor: Colors.black, // 阴影
      shadowColor: Colors.transparent, // 去掉阴影
      elevation: 0.5, // 阴影高度
      side: BorderSide(color: outlineColor ?? bottonFontColor, width: 1),
      shape: RoundedRectangleBorder(
        // 形状
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }
}
