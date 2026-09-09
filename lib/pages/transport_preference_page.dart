import 'package:flutter/material.dart';
import '../models/trip_models.dart';
import '../theme/app_colors.dart';

/// 出行偏好：行程类型（3类） + 跨城交通偏好 + 同城交通偏好
class TransportPreferencePage extends StatefulWidget {
  final TripMode initialMode;
  final TransportType initialIntercity;
  final TransportType initialIntraCity;

  const TransportPreferencePage({
    super.key,
    this.initialMode = TripMode.pureTransit,
    this.initialIntercity = TransportType.flight,
    this.initialIntraCity = TransportType.taxi,
  });

  @override
  State<TransportPreferencePage> createState() => _TransportPreferencePageState();
}

class _TransportPreferencePageState extends State<TransportPreferencePage> {
  late TripMode _tripMode = widget.initialMode;
  late TransportType _intercityPref = widget.initialIntercity;
  late TransportType _intraCityPref = widget.initialIntraCity;

  @override
  Widget build(BuildContext context) {
    final isDrive = _tripMode == TripMode.pureDrive;
    return Scaffold(
      backgroundColor: AppColors.mintBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('出行偏好', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '行程类型',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            '决定跨城怎么走、要不要出现交通枢纽',
            style: TextStyle(fontSize: 12, color: AppColors.textSub),
          ),
          const SizedBox(height: 12),
          _modeOption(TripMode.pureDrive, '🚗 纯自驾', '全程自己开车，无交通枢纽，长距离自动提示服务区'),
          const SizedBox(height: 8),
          _modeOption(TripMode.pureTransit, '🚄 纯公共交通', '跨城坐火车/飞机/大巴/轮船，自动安排车站机场，市内地铁公交打车'),
          const SizedBox(height: 8),
          _modeOption(TripMode.transitPlusRental, '🛬 公共交通 + 落地租车', '跨城公共交通，到达后租车自驾，自动插入租车点'),
          if (!isDrive) ...[
            const SizedBox(height: 24),
            const Text(
              '跨城交通偏好',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            _prefOption(true, TransportType.flight, '✈️ 飞机优先', '适合长距离跨省出行', Icons.flight),
            const SizedBox(height: 8),
            _prefOption(true, TransportType.highSpeedTrain, '🚄 高铁优先', '舒适快捷，覆盖广', Icons.train),
            const SizedBox(height: 8),
            _prefOption(true, TransportType.bus, '🚌 大巴', '灵活经济，覆盖县域', Icons.directions_bus),
            const SizedBox(height: 8),
            _prefOption(true, TransportType.ship, '⛴️ 轮船', '轮渡/客运航线', Icons.directions_boat),
            const SizedBox(height: 24),
            const Text(
              '同城交通偏好',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              _tripMode == TripMode.transitPlusRental ? '落地取车后同城均为自驾，此偏好用于取车前' : 'AI 将按距离自动搭配（<1.5km 步行）',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 12),
            _prefOption(false, TransportType.taxi, '🚕 打车', '方便快捷，点到点', Icons.local_taxi),
            const SizedBox(height: 8),
            _prefOption(false, TransportType.subway, '🚇 地铁', '经济实惠，不堵车', Icons.subway),
            const SizedBox(height: 8),
            _prefOption(false, TransportType.bus, '🚌 公交', '最经济的选择', Icons.directions_bus),
          ],
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'tripMode': _tripMode,
                  'bigTransport': _intercityPref,
                  'smallTransport': _intraCityPref,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
              child: const Text('确定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeOption(TripMode value, String title, String subtitle) {
    final isSelected = _tripMode == value;
    return GestureDetector(
      onTap: () => setState(() => _tripMode = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.mintCircle : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.green : const Color(0xFFE3EDE2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.greenDark : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.4)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: AppColors.green),
          ],
        ),
      ),
    );
  }

  Widget _prefOption(bool isIntercity, TransportType value, String title, String subtitle, IconData icon) {
    final current = isIntercity ? _intercityPref : _intraCityPref;
    final isSelected = current == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isIntercity) {
            _intercityPref = value;
          } else {
            _intraCityPref = value;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.mintCircle : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.green : const Color(0xFFE3EDE2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.green : AppColors.mintBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : AppColors.textSub),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.greenDark : AppColors.textPrimary,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}
