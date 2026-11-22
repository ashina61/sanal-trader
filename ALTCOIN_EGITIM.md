# Altcoin evreni ve eğitim (v0.3)

**Site:** https://ashina61.github.io/sanal-trader/

## Piyasa keşfi

Sabit 6 coinden daha geniş evrene geçildi. `GET /api/v3/ticker/24hr` ile Binance Spot USDT çiftleri değerlendirilir; işlem hacmi en yüksek **72 uygun çift** izlenir. Bu liste sürekli sabit değildir; market erişimine göre değişebilir. USDT/TRY döviz dönüşüm çifti ayrıca izlenir. Ürün adları Binance sembolünden gelir ve her token için tam kimlik eşlemesi anlamına gelmez.

Düşük hacimli (<2 milyon USDT/24s), desteklenmeyen, stablecoin/fiat ve isimden tanınan kaldıraçlı çiftler başlangıç elemesinden geçemez. Bu filtre **riskin sıfır olduğu anlamına gelmez**.

İlk 36 likit çiftin saatlik kapanış geçmişi için ayrı REST çağrıları yapılır. Veri gelmeyen coin listede görünebilir ama geçmişe dayalı bot AL sinyali oluşturmaz.

## Öğrenme süreci

1. Botun 3 sinyalci stratejisi: 6 saatlik fiyat eğilimi, 24s momentum ve ters-yön.
2. Geçmişte saatlik fiyatlardan önceki 24s değişimi ve son 6 saat üzerinden sinyal oluşturulur; tahmin **bir sonraki saatin** fiyatıyla ölçülür.
3. Son 24 saatlik fiyatlar **eğitime katılmaz**. Önceki saatlerin yön sonuçlarına göre model ağırlıkları eğitilir.
4. Ayrılan son 24 saatlik bölümde tahmin doğruluğu ve 24s momentum temel modelinin doğruluğu gösterilir. Bu başarı oranı **kârı, işlem maliyetini veya gerçek yatırım performansını göstermez**.
5. Sonraki fiyatlar geldikçe canlı yön tahmini doğruluğu ölçülür, strateji ağırlıkları uyarlanır. Öğrenme geçmişi bu tarayıcıda korunur.

Bot yalnızca sanal emir yapar; 650 TL sanal bakiyeyle başlar, toplam %65 maruziyet ve günlük 8 emir sınırı vardır. Risk kuralları yeni emri engelleyebilir. **Geriye dönük verilerle geçmişte gerçek işlem yapmış gibi işlem geçmişi yaratılmaz.**

## Bilinen sınırlamalar

- Coin taraması yalnızca Binance Spot USDT çiftleri ve belirlenen eşiklerle sınırlıdır; tüm global kripto tokenleri değildir.
- Bazı semboller hâlâ yüksek riskli veya yeni listelenmiş olabilir. Canlı akış ve geçmiş mumlar bölgesel/yük erişim sınırlarına tabidir.
- Saatlik OHLC yerine önce kapanış serisi kullanılır, bid/ask spread, vergi ve gerçek emir defteri etkileri modellenmez.
- Eğitim bir dil modeli veya büyük sinir ağı değildir. İstatistiksel, çevrim içi ağırlıklandırmadır.
- Kullanıcı tarayıcıyı kapatırsa bot durur; portföy ve öğrenme farklı tarayıcılarla paylaşılmaz.
