# Canlı SanalTrader

Sitenin adresi: https://ashina61.github.io/sanal-trader/

## Fiyatların kaynağı

1. Binance'in yalnızca halka açık piyasa verisi veren `data-api.binance.vision` sunucusundan başlangıç fiyatları, 24s değişimleri ve 1 saatlik geçmiş mum kapanışları alınır.
2. `wss://data-stream.binance.vision/ws/!miniTicker@arr` tek toplu WebSocket akışından bütün piyasanın değişmiş miniTicker olayları gelir; yerel likidite listesi ve USDT/TRY kuru üzerinden ilgililer işlenir.
3. Coinin USDT fiyatı **gerçek USDT/TRY alışveriş çiftinin fiyatıyla** çarpılır; hiçbir sabit döviz kuru veya simüle edilmiş fiyat üretilmez. Canlı 24s değişim USDT ve USDT/TRY değişiminden türetilir.
4. Başlangıç grafiği Binance 1saat USDT kapanışlarına o anki USDT/TRY çarpanı uygulanarak oluşturulur. **Geçmiş saatlerin gerçek TRY fiyat grafiği olduğu iddia edilmez.**
5. Binance REST erişilemezse CoinGecko TRY fiyatları yedek olarak denenir. WebSocket erişilemiyorsa belirli aralıklarla REST üzerinden yenilenir. Her iki kaynak yoksa *sahte fiyat gösterilmez* ve bot emir veremez.
6. CANLI simgesi yalnızca son 30 saniyede doğrulanmış coin TRY fiyatı geldiyse gösterilir.

## Bot nasıl çalışıyor?

- Yerel bot yeni kurulumlarda kapalıdır. Bot sekmesindeki anahtardan açıkça açılabilir; mevcut kayıtlı açık/kapalı tercih korunur. Bu anahtar yalnızca tarayıcı botunu kontrol eder.
- Canlı fiyatlar görünür ve günlük limit izin verirse yeni sanal işlemleri onaysız yapabilir; risk kuralları kararı bekletebilir.
- Sanal başlangıç ₺650; tek emir en çok portföyün %12'si; toplam pozisyon üst sınırı %65; nakit rezervi minimum %30.
- En çok 8 günlük işlem, coine özel 30 dk tekrar sınırı ve yaklaşık %6 zarar koruması / %8 kâr hedefi.
- Yaklaşık 45 saniyede bir stratejilerini değerlendirir ve önceki sinyallerin sonraki 15 dakika sonuçlarından strateji ağırlığını günceller. **Kâr garantisi yoktur; online istatistiksel ağırlıklandırmadır.**
- Emirler yalnızca yerel sanal cüzdan motoruna gider. Kullanıcıların kripto borsa hesabına erişim, emir gönderme, yatırma veya para çekme olanağı **yoktur**.

## Yayın

GitHub Actions 'Publish SanalTrader Web' yeni main commitlerinde web derlemesini otomatik yayımlar. **Yerel bot** yalnızca tarayıcı açıkken işler. **Ayrı 1x sanal LONG/SHORT sunucu botu** ise `Free Scheduled Paper Bot` iş akışında yaklaşık beş dakikada bir çalışması için zamanlanmıştır. Sunucu sanal kasası `bot-data/state.json` içinde tutulur, tarayıcı kasasıyla birleştirilmez; GitHub cron gecikebilir/atlanabilir. Kapatma, devam ettirme ve reset Actions menüsündedir.
