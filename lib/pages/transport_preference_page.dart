import 'package:flutter/material.dart';
import '../models/trip_models.dart';

class TransportPreferencePage extends StatefulWidget {
  const TransportPreferencePage({super.key});

  @override
  State<TransportPreferencePage> createState() => _TransportPreferencePageState();
}

class _TransportPreferencePageState extends State<TransportPreferencePage> {
  TransportCategory _bigTransport = TransportCategory.big; // 大交通：飞机/高铁
  TransportCategory _smallTransport = TransportCategory.small; // 小交通：打车/地铁

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF89CFF0), Color(0xFF6BB3E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        '交通偏好设置',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '选择您的出行偏好',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '跨城和同城交通将根据您的偏好自动安排',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),

                // 大交通选择
                _buildSectionTitle('🚄 跨城交通（大交通）'),
                const SizedBox(height: 12),
                _buildBigTransportOption(
                  TransportCategory.big,
                  '✈️ 飞机优先',
                  '适合长距离跨省出行',
                  Icons.flight,
                ),
                const SizedBox(height: 8),
                _buildBigTransportOption(
                  TransportCategory.train,
                  '🚄 高铁优先',
                  '舒适快捷，覆盖广',
                  Icons.train,
                ),
                const SizedBox(height: 24),

                // 小交通选择
                _buildSectionTitle('🚗 同城交通（小交通）'),
                const SizedBox(height: 12),
                _buildSmallTransportOption(
                  TransportCategory.taxi,
                  '🚕 打车',
                  '方便快捷，点到点',
                  Icons.local_taxi,
                ),
                const SizedBox(height: 8),
                _buildSmallTransportOption(
                  TransportCategory.subway,
                  '🚇 地铁',
                  '经济实惠，不堵车',
                  Icons.subway,
                ),
                const SizedBox(height: 8),
                _buildSmallTransportOption(
                  TransportCategory.bus,
                  '🚌 公交',
                  '最经济的选择',
                  Icons.directions_bus,
                ),
              ],
            ),
          ),

          // Confirm Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'bigTransport': _bigTransport,
                      'smallTransport': _smallTransport,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF89CFF0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '确定',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildBigTransportOption(
    TransportCategory value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _bigTransport == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _bigTransport = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF89CFF0).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF89CFF0) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF89CFF0) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : Colors.grey[600]),
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
                      color: isSelected ? const Color(0xFF89CFF0) : Colors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF89CFF0)),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallTransportOption(
    TransportCategory value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _smallTransport == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _smallTransport = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF89CFF0).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF89CFF0) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF89CFF0) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : Colors.grey[600]),
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
                      color: isSelected ? const Color(0xFF89CFF0) : Colors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF89CFF0)),
          ],
        ),
      ),
    );
  }
}
