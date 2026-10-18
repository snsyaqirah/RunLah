import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../services/weather_service.dart';

Color heatColor(HeatRisk r) => switch (r) {
      HeatRisk.low => RL.green,
      HeatRisk.moderate => RL.amber,
      HeatRisk.high => const Color(0xFFE5602A),
      HeatRisk.extreme => RL.red,
    };

String heatLabel(HeatRisk r) => switch (r) {
      HeatRisk.low => tr('Low'),
      HeatRisk.moderate => tr('Moderate'),
      HeatRisk.high => tr('High'),
      HeatRisk.extreme => tr('Extreme'),
    };

String heatAdvice(HeatRisk r) => switch (r) {
      HeatRisk.low => tr('Good running conditions. Drink to thirst at the water stations.'),
      HeatRisk.moderate => tr('Humid KL air. Sip water at every station and start 5–10 s/km slower than goal pace.'),
      HeatRisk.high => tr('Hot and humid. Slow down 15–20 s/km, drink at every station and pour water over your head.'),
      HeatRisk.extreme => tr('Dangerous heat. Run for the finish, not the time: take walk breaks and stop at a medic tent if you feel dizzy.'),
    };

String weatherLabel(int code) => switch (code) {
      0 => tr('Clear sky'),
      1 => tr('Mainly clear'),
      2 => tr('Partly cloudy'),
      3 => tr('Overcast'),
      45 || 48 => tr('Fog'),
      >= 51 && <= 57 => tr('Drizzle'),
      >= 61 && <= 67 => tr('Rain'),
      >= 80 && <= 82 => tr('Rain showers'),
      >= 95 => tr('Thunderstorm'),
      _ => tr('Cloudy'),
    };

IconData weatherIcon(int code) => switch (code) {
      0 || 1 => Icons.wb_sunny_rounded,
      2 => Icons.wb_cloudy_rounded,
      3 => Icons.cloud_rounded,
      45 || 48 => Icons.foggy,
      >= 51 && <= 67 => Icons.grain_rounded,
      >= 80 && <= 82 => Icons.water_drop_rounded,
      >= 95 => Icons.thunderstorm_rounded,
      _ => Icons.cloud_rounded,
    };

/// Weather at the start line and the heat-risk alert (idea pool:
/// "Heat and weather alert").
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WeatherService>();
    final w = ws.now;
    final risk = w.risk;
    final color = heatColor(risk);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            tr('Weather at the start'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pill(w.estimated ? tr('Estimated') : tr('Live'), color: w.estimated ? RL.slate : RL.green),
                SizedBox(
                  width: 32,
                  height: 24,
                  child: ws.loading
                      ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: tr('Refresh'),
                          onPressed: ws.refresh,
                          icon: Icon(Icons.refresh_rounded, color: muted(context)),
                        ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: RL.teal.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(16)),
                child: Icon(weatherIcon(w.weatherCode), color: RL.teal, size: 28),
              ),
              const SizedBox(width: 12),
              Text(
                '${w.temperatureC.round()}°',
                style: TextStyle(fontSize: 38, height: 1, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(weatherLabel(w.weatherCode), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                    const SizedBox(height: 2),
                    Text(
                      tr('Feels like {f}° · Humidity {h}%', {'f': w.feelsLikeC.round(), 'h': w.humidityPct.round()}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.35))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(risk.index >= HeatRisk.high.index ? Icons.warning_amber_rounded : Icons.thermostat_rounded, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('Heat risk: {level}', {'level': heatLabel(risk)}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w900, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _RiskMeter(risk: risk),
                const SizedBox(height: 8),
                Text(heatAdvice(risk), style: TextStyle(fontSize: 13, height: 1.35, color: ink(context))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            w.estimated
                ? tr('{place} · typical KL dawn values (offline estimate)', {'place': WeatherService.placeName})
                : tr('{place} · Open-Meteo · wind {wind} km/h · {time}', {'place': WeatherService.placeName, 'wind': w.windKph.round(), 'time': fmtClock(w.observedAt)}),
            style: TextStyle(fontSize: 11.5, color: muted(context)),
          ),
        ],
      ),
    );
  }
}

class _RiskMeter extends StatelessWidget {
  const _RiskMeter({required this.risk});
  final HeatRisk risk;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in HeatRisk.values) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: r == risk ? 8 : 5,
                  decoration: BoxDecoration(
                    color: r.index <= risk.index ? heatColor(r) : heatColor(r).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  heatLabel(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: r == risk ? FontWeight.w900 : FontWeight.w600, color: r == risk ? heatColor(r) : muted(context)),
                ),
              ],
            ),
          ),
          if (r != HeatRisk.values.last) const SizedBox(width: 4),
        ],
      ],
    );
  }
}
