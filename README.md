# SanalTrader — tek beyin, tek sanal kasa

**Canlı uygulama:** https://ashina61.github.io/sanal-trader/

Bu uygulama **gerçek kripto borsasına emir göndermez ve gerçek para kullanmaz**.
Yalnızca başlangıç değeri **650 TL** olan tek bir sanal portföyü takip eder.

## Nasıl çalışıyor?

1. GitHub Actions içindeki `Free Scheduled Paper Bot` Python motoru,
   Binance'ten güncel kamuya açık USDT/TRY kurunu ve likit spot coin verilerini okur.
2. Saatlik teknik trendi ve uygun coinlerde **gerçek kapalı 15 dakikalık mumları**
   analiz eder. Groq AI yalnızca risk motorunun onayladığı AL/SHORT giriş
   adaylarını seçebilir veya BEKLE diyebilir.
3. Normal SPOT AL, SPOT SAT, 1x sanal SHORT AÇ ve SHORT KAPAT kararları tek sunucu cüzdanının
   `bot-data/state.json` kaydına işlenir. Stop, teminat ve zorunlu koruyucu
   çıkışlar AI onayına bağlı değildir.
4. Web ve Android arayüzü sunucu cüzdanını **salt okunur** olarak gösterir.
   **Başka demo cüzdanı, yerel bot, manuel emir veya Firebase hesabı yoktur.**

**Ekranlar:** Kasa (net bakiye ve açık pozisyonlar), Radar (gerçek bot adayları
ve ret gerekçeleri), Bot (son karar ve AI durumu), Kâr (net büyüme ve kapanışlar).

## Neden bazen işlem yapmıyor?

Botun amacı işlem sayısını yükseltmek değil, **sanal sermayeyi komisyon
sonrası büyütmeye çalışırken kaybı sınırlamaktır**. 16 günlük sanal emir
üst sınırı, yaklaşık %65 toplam pozisyon maruziyeti, en az %30 nakit rezervi
ve mevcut stop/kâr koruma şartları nedeniyle BEKLE kararları olabilir.
Kasa dolduğunda yalnızca doğrulanmış olumsuz momentum koşullarında
kontrollü risk azaltımı yapılır. Hiçbir sonuç veya kâr garantisi yoktur.

## Tarayıcı kapalıyken çalışması

- GitHub Actions takvimi: yaklaşık 5 dakikalık kron; GitHub bu
  tetiklemeleri geciktirebilir veya atlayabilir.
- Kullanıcının kurduğu **isteğe bağlı** Cloudflare Worker, her 5 dakikada
  GitHub `workflow_dispatch` başlatmayı dener. Bu, arka plan sürekliliğini
  artırır fakat gerçek zamanlı 7/24 SLA sağlamaz.
- Durumu izle:
  https://github.com/ashina61/sanal-trader/actions/workflows/paper-bot.yml
- Groq gerçek bağlantı deneyi hiçbir sanal emir açmadan:
  https://github.com/ashina61/sanal-trader/actions/workflows/ai-health.yml
- **`reset` kullanma:** Mevcut sanal kasa ve geçmiş işlemleri sıfırlar.

## Kodu ve güncellemeleri izleme

`backend/paper_bot.py` — tek sanal motor,
`backend/ai_brain.py` — kısıtlı Groq kararı,
`lib/screens/home_screen.dart` — tek sunucu arayüzü,
`assets/changelog.json` — uygulamanın Güncelleme Geçmişi.

Uygulamanın eski tarayıcı demo modülleri ve artık kullanılmayan
Firebase, yerel depolama, manuel emir ve yerel öğrenme testleri silindi.
Sanal botun `bot-data` dalındaki geçmişi, açık pozisyonları ve bakiyesi
**korundu**.

**Yatırım tavsiyesi değildir.** Veri kaynakları, sanal komisyonlar ve
otomatik çalıştırma gerçek ticaretin tüm risk ve maliyetlerini yansıtmaz.
