import 'package:flutter_test/flutter_test.dart';
import 'package:plana_app/core/net/nai_client.dart';

/// NAI 5 的 Opus 充电式额度:响应解析 + 派生读数。
///
/// 这套算法的常数(17.3 张/%、86400 秒/天)是照抄官方前端的,界面上电池条、
/// 「约多少张」、「回充多快」全从这里取数 —— 钉住,免得日后有人顺手改成
/// 「差不多的」数字,四处读数就各自漂了。
void main() {
  NaiUsage u({
    double pct = 50,
    bool neg = false,
    int secs = 0,
    int n = 1,
    double extra = 0,
  }) => (
    percent: pct,
    isNegative: neg,
    secondsToNextPct: secs,
    accounts: n,
    purchasedPercent: extra,
  );

  group('usage 块解析', () {
    test('整块缺省 → null(非 Opus / 老服务端)', () {
      expect(parseNaiUsage(null), isNull);
      expect(parseNaiUsage('nope'), isNull);
      expect(parseNaiUsage(const {}), isNull);
    });

    test('percent 读不到就整块作废,不拿 0 顶上冒充「已耗尽」', () {
      expect(parseNaiUsage(const {'isNegative': true}), isNull);
      expect(parseNaiUsage(const {'percentage': 87.4}), isNull);
    });

    test('只有 percent 也认:其余按缺省兜住', () {
      final v = parseNaiUsage(const {'percent': 87.4})!;
      expect(v.percent, 87.4);
      expect(v.isNegative, isFalse);
      expect(v.secondsToNextPct, 0);
      expect(v.accounts, 1); // 直连响应没这个字段,单号
    });

    test('accounts 来自 bot 线的合并块;不合法的值兜到 1', () {
      expect(parseNaiUsage(const {'percent': 60, 'accounts': 3})!.accounts, 3);
      expect(parseNaiUsage(const {'percent': 60, 'accounts': 0})!.accounts, 1);
      expect(parseNaiUsage(const {'percent': 60, 'accounts': -2})!.accounts, 1);
    });

    test('整数 percent 收成 double', () {
      expect(parseNaiUsage(const {'percent': 87})!.percent, 87.0);
    });

    test('三项齐全', () {
      final v = parseNaiUsage(const {
        'percent': 87.4,
        'isNegative': false,
        'timeUntilNextPercent': 6048,
      })!;
      expect(v.percent, 87.4);
      expect(v.isNegative, isFalse);
      expect(v.secondsToNextPct, 6048);
    });

    test('purchasedPercent:缺省 0,负数兜到 0', () {
      expect(parseNaiUsage(const {'percent': 60})!.purchasedPercent, 0);
      expect(
        parseNaiUsage(const {
          'percent': 60,
          'purchasedPercent': 200,
        })!.purchasedPercent,
        200.0,
      );
      expect(
        parseNaiUsage(const {
          'percent': 60,
          'purchasedPercent': -5,
        })!.purchasedPercent,
        0,
      );
    });
  });

  group('加购额度(Extra Usage)', () {
    test('合计 = 常规 + 加购,加购不封顶 100', () {
      expect(u(pct: 80, extra: 300).extraPct, 300);
      expect(u(pct: 80, extra: 300).totalPct, 380);
    });

    test('常规用完时读数只剩加购', () {
      expect(u(pct: 0, extra: 150).totalPct, 150);
    });

    test('张数按合计折算', () {
      expect(u(pct: 100, extra: 400).imagesRemaining, 8650); // 17.3 × 500
    });

    test('距充满只看常规额度', () {
      expect(u(pct: 90, secs: 86400, extra: 200).daysToFull, closeTo(10, 1e-9));
    });

    test('加购还有 5% 以上就不算低电', () {
      expect(u(pct: 0, extra: 50).isLowOrEmpty, isFalse);
      expect(u(pct: 3, extra: 4).isLowOrEmpty, isTrue);
    });
  });

  group('电池百分比(池子合计)', () {
    test('越界值夹回 0~满值', () {
      expect(u(pct: 100.4).batteryPct, 100);
      expect(u(pct: -3).batteryPct, 0);
    });

    test('已耗尽按 0 显示(接口没说跌了多深)', () {
      expect(u(pct: 42, neg: true).batteryPct, 0);
    });

    test('多号:读数是**相加**,不是平均 —— 满值也跟着涨到 100N', () {
      // 线上那份:5 个号平均 74.8% ⇒ 界面报 374%,而不是 74%
      expect(u(pct: 74.8, n: 5).fullPct, 500);
      expect(u(pct: 74.8, n: 5).batteryPct, closeTo(374, 1e-9));
      // 满仓 2 号 = 200%,不能夹到 100
      expect(u(pct: 100, n: 2).batteryPct, 200);
    });

    test('单号时满值仍是 100(直连线看不出区别)', () {
      expect(u(pct: 60).fullPct, 100);
      expect(u(pct: 60).batteryPct, 60);
    });
  });

  group('折算张数', () {
    test('满值 100% ≈ 1730 张', () {
      expect(u(pct: 100).imagesRemaining, 1730);
    });

    test('按 17.3 张/% 线性折算', () {
      expect(u(pct: 87.4).imagesRemaining, 1512); // 17.3 × 87.4 = 1512.02
      expect(u(pct: 0).imagesRemaining, 0);
    });

    test('耗尽时是 0 张,不按 percent 算', () {
      expect(u(pct: 42, neg: true).imagesRemaining, 0);
    });

    test('多号合并:按合计读数折算(号数已在 batteryPct 里,不再乘一遍)', () {
      // 三个号平均还剩 60% ⇒ 合计 180% ⇒ 17.3 × 180
      expect(u(pct: 60, n: 3).imagesRemaining, 3114);
      expect(u(pct: 60, n: 1).imagesRemaining, 1038);
    });
  });

  group('回充速率', () {
    test('86400 ÷ 每 1% 秒数,保留一位小数', () {
      expect(u(secs: 6048).refillPctPerDay, 14.3); // 86400/6048 = 14.285…
      expect(u(secs: 86400).refillPctPerDay, 1.0);
    });

    test('拿不到回充节奏就是 0,不是无穷', () {
      expect(u(secs: 0).refillPctPerDay, 0);
      expect(u(secs: -1).refillPctPerDay, 0);
    });

    test('小时速率不预先取整:0.6%/时 这个量级取整就成 0 了', () {
      expect(u(secs: 6048).refillPctPerHour, closeTo(0.5952, 1e-4));
      expect(u(secs: 6048).imagesPerHour, 10); // 17.3 × 0.5952 = 10.29
      // 慢到一天才回 1%,按小时仍算得出张数,不会被压成 0
      expect(u(secs: 86400).imagesPerHour, 1); // 17.3 × 0.0417 = 0.72 → 1
    });

    test('拿不到回充节奏时小时速率也是 0', () {
      expect(u(secs: 0).refillPctPerHour, 0);
      expect(u(secs: 0).imagesPerHour, 0);
    });

    test('多号合并:每个号都在各自回充,速率与张数都按号数放大', () {
      // 速率与读数同口径(都是池子合计),不然「24 小时后到几成」会算错
      expect(u(secs: 6048, n: 3).refillPctPerHour, closeTo(1.7857, 1e-4));
      expect(u(secs: 6048, n: 3).imagesPerHour, 31); // 17.3 × 1.7857
      expect(u(secs: 86400, n: 3).refillPctPerDay, 3.0);
    });
  });

  group('距充满', () {
    test('按**当前**的缺口算,不是充满一整轮的时间', () {
      // 剩 90%、每天回 1% → 还差 10 天;整轮是 100 天,别读成那个
      expect(u(pct: 90, secs: 86400).daysToFull, closeTo(10, 1e-9));
    });

    test('多号:缺口与速率都按池子合计,算出来仍是同一个天数', () {
      // 2 号各剩 90% ⇒ 合计 180/200,速率 2%/天 ⇒ 仍是 10 天
      expect(u(pct: 90, secs: 86400, n: 2).daysToFull, closeTo(10, 1e-9));
    });

    test('满电就是 0 天', () {
      expect(u(pct: 100, secs: 86400).daysToFull, 0);
      expect(u(pct: 100, secs: 86400, n: 4).daysToFull, 0);
    });

    test('不回充时为 null(界面显示「—」)', () {
      expect(u(pct: 50, secs: 0).daysToFull, isNull);
    });
  });

  group('低电量', () {
    test('5% 是分界', () {
      expect(u(pct: 5).isLowOrEmpty, isFalse);
      expect(u(pct: 4.9).isLowOrEmpty, isTrue);
    });

    test('耗尽恒为真,不看 percent', () {
      expect(u(pct: 80, neg: true).isLowOrEmpty, isTrue);
    });

    test('门槛读单号原值:5 个号各剩 4%(合计 20%)照样算低电量', () {
      expect(u(pct: 4, n: 5).isLowOrEmpty, isTrue);
    });
  });
}
