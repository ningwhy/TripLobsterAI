import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/day_weather.dart';

void main() {
  final openMeteo = <String, dynamic>{
    'daily': <String, dynamic>{
      'time': <dynamic>['2026-10-01', '2026-10-02', '2026-10-03'],
      'temperature_2m_max': <dynamic>[25.4, 22.0, 19.0],
      'temperature_2m_min': <dynamic>[14.2, 13.0, 11.0],
      'weather_code': <dynamic>[0, 61, 95],
      'wind_speed_10m_max': <dynamic>[10.4, 12.0, 8.0],
      'wind_direction_10m_dominant': <dynamic>[315, 90, 180],
    },
  };

  group('DayWeather 解析', () {
    test('① 按日期取（保证徽章日期 == 分组头日期，M4）', () {
      final w = DayWeather.fromOpenMeteoByDate(openMeteo, '2026-10-01')!;
      expect(w.date, '2026-10-01');
      expect(w.max, 25.4);
      expect(w.min, 14.2);
    });

    test('② WMO 0 → 晴 ☀️', () {
      final w = DayWeather.fromOpenMeteoByDate(openMeteo, '2026-10-01')!;
      expect(w.desc, '晴');
      expect(w.iconEmoji, '☀️');
    });

    test('③ 温度文案 25°/14°', () {
      expect(DayWeather.fromOpenMeteoByDate(openMeteo, '2026-10-01')!.tempText, '25°/14°');
    });

    test('④ 风文案（WX-02 + 16 方位）', () {
      expect(DayWeather.fromOpenMeteoByDate(openMeteo, '2026-10-01')!.windText, 'NW 10km/h');
      expect(DayWeather.fromOpenMeteoByDate(openMeteo, '2026-10-02')!.windText, 'E 12km/h');
    });

    test('⑤ 超出 16 天窗口 → null（整块隐藏，不用末日充数，A-8）', () {
      expect(DayWeather.fromOpenMeteoByDate(openMeteo, '2026-11-01'), isNull);
    });

    test('⑥ 按下标取（设计文档签名）', () {
      expect(DayWeather.fromOpenMeteo(openMeteo, 1)!.date, '2026-10-02');
      expect(DayWeather.fromOpenMeteo(openMeteo, 99), isNull);
      expect(DayWeather.fromOpenMeteo(openMeteo, -1), isNull);
    });

    test('⑦ 缺风字段（WX-02 之前的服务端）→ windText null，不崩', () {
      final noWind = <String, dynamic>{
        'daily': <String, dynamic>{
          'time': <dynamic>['2026-10-01'],
          'temperature_2m_max': <dynamic>[20.0],
          'temperature_2m_min': <dynamic>[10.0],
          'weather_code': <dynamic>[3],
        },
      };
      final w = DayWeather.fromOpenMeteoByDate(noWind, '2026-10-01')!;
      expect(w.windText, isNull);
      expect(w.desc, '阴');
    });

    test('⑧ daily 结构异常 → null', () {
      expect(DayWeather.fromOpenMeteoByDate(<String, dynamic>{}, '2026-10-01'), isNull);
    });
  });

  group('WMO 映射表（PRD §5.5 全覆盖）', () {
    const table = <int, String>{
      0: '晴', 1: '大部晴朗', 2: '局部多云', 3: '阴', 45: '雾', 48: '雾凇',
      51: '毛毛雨', 53: '毛毛雨', 55: '毛毛雨', 56: '冻毛毛雨', 57: '冻毛毛雨',
      61: '小雨', 63: '中雨', 65: '大雨', 66: '冻雨', 67: '冻雨',
      71: '小雪', 73: '中雪', 75: '大雪', 77: '米雪',
      80: '阵雨', 81: '阵雨', 82: '阵雨', 85: '阵雪', 86: '阵雪',
      95: '雷阵雨', 96: '雷暴伴冰雹', 99: '雷暴伴冰雹',
    };
    test('① 全部命中且非"未知"', () {
      for (final e in table.entries) {
        expect(DayWeather.wmoDesc(e.key), e.value, reason: 'code=${e.key}');
        expect(DayWeather.wmoEmoji(e.key), isNot('🌀'), reason: 'code=${e.key}');
      }
    });
    test('② 未命中 → 未知 🌀', () {
      expect(DayWeather.wmoDesc(999), '未知');
      expect(DayWeather.wmoEmoji(999), '🌀');
      expect(DayWeather.wmoDesc(-1), '未知');
    });
  });

  group('16 方位换算', () {
    test('① 扇区中心', () {
      // 不能写 const：key 含 double（22.5/67.5…），const map 的 key 不允许重写 ==/hashCode
      final centers = <num, String>{
        0: 'N', 22.5: 'NNE', 45: 'NE', 67.5: 'ENE', 90: 'E', 112.5: 'ESE',
        135: 'SE', 157.5: 'SSE', 180: 'S', 202.5: 'SSW', 225: 'SW', 247.5: 'WSW',
        270: 'W', 292.5: 'WNW', 315: 'NW', 337.5: 'NNW',
      };
      for (final e in centers.entries) {
        expect(DayWeather.windDir16(e.key), e.value, reason: 'deg=${e.key}');
      }
    });
    test('② 扇区下界（闭区间）', () {
      expect(DayWeather.windDir16(11.25), 'NNE');
      expect(DayWeather.windDir16(348.75), 'N');
      expect(DayWeather.windDir16(11.24), 'N');
      expect(DayWeather.windDir16(348.74), 'NNW');
    });
    test('③ 归一化（360 / 负数 / 越界）', () {
      expect(DayWeather.windDir16(360), 'N');
      expect(DayWeather.windDir16(-1), 'N');
      expect(DayWeather.windDir16(-12), 'NNW');
      expect(DayWeather.windDir16(720), 'N');
      expect(DayWeather.windDir16(405), 'NE');
    });
    test('④ null / 非法 → 空串（隐藏风向，只显风速）', () {
      expect(DayWeather.windDir16(null), '');
      expect(DayWeather.windDir16(double.nan), '');
    });
  });
}
