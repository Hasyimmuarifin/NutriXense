class PumpFlowRate {
  final int pumpIndex;
  final int relay;
  final String pumpName;
  final double averageMlPerSecond;

  const PumpFlowRate({
    required this.pumpIndex,
    required this.relay,
    required this.pumpName,
    required this.averageMlPerSecond,
  });
}

class PumpFlowRates {
  PumpFlowRates._();

  static const List<PumpFlowRate> values = [
    PumpFlowRate(
      pumpIndex: 0,
      relay: 1,
      pumpName: 'Pompa A',
      averageMlPerSecond: 34.77,
    ),
    PumpFlowRate(
      pumpIndex: 1,
      relay: 2,
      pumpName: 'Pompa B',
      averageMlPerSecond: 38.55,
    ),
    PumpFlowRate(
      pumpIndex: 2,
      relay: 3,
      pumpName: 'Pompa C',
      averageMlPerSecond: 29.99,
    ),
    PumpFlowRate(
      pumpIndex: 3,
      relay: 4,
      pumpName: 'Pompa D',
      averageMlPerSecond: 35.00,
    ),
  ];

  static PumpFlowRate byPumpIndex(int pumpIndex) {
    return values.firstWhere(
      (item) => item.pumpIndex == pumpIndex,
      orElse: () => values.first,
    );
  }

  static PumpFlowRate byRelay(int relay) {
    return values.firstWhere(
      (item) => item.relay == relay,
      orElse: () => values.first,
    );
  }

  static PumpFlowRate get highestRate {
    return values.reduce(
      (current, next) => current.averageMlPerSecond >= next.averageMlPerSecond
          ? current
          : next,
    );
  }

  static double volumeForDuration({
    required int pumpIndex,
    required int seconds,
  }) {
    return byPumpIndex(pumpIndex).averageMlPerSecond * seconds;
  }

  static int secondsForVolume({
    required int pumpIndex,
    required double volumeMl,
  }) {
    final rate = byPumpIndex(pumpIndex).averageMlPerSecond;
    if (rate <= 0) return 1;
    final seconds = (volumeMl / rate).round();
    return seconds < 1 ? 1 : seconds;
  }

  static String formatMl(double value) {
    final fixed = value.toStringAsFixed(value >= 100 ? 0 : 1);
    return fixed.replaceFirst(RegExp(r'\.0$'), '');
  }

  static String formatRate(double value) {
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  }

  static Map<String, double> toPromptJson() {
    return {
      for (final item in values) item.pumpName: item.averageMlPerSecond,
    };
  }
}
