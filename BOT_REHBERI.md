# SanalTrader — Öğrenen sanal bot

**Sürüm:** v0.9.1. Bu rehber **tarayıcıdaki yerel sanal botu** açıklar. Ayrıca ücretsiz GitHub Actions ile zamanlanan, **ayrı sanal kasalı** LONG/SHORT sunucu botu vardır.

## Başlatma

1. https://ashina61.github.io/sanal-trader/ adresinden uygulamayı aç.
2. Alttan **Bot** sekmesine gel.
3. Açma düğmesini etkinleştir; risk uyarısını onayla.
4. İşlem günlüğünü, strateji ağırlıklarını ve doğruluk göstergesini izle.
5. Durdurmak için aynı anahtarı kapat.

Bot **ilk kurulumda kapalıdır**. Onaydan sonra aktif durumu bu tarayıcıda saklanır. Tarayıcı kapalıyken işlem yapılmaz; tekrar açıldığında aktif durumdan devam eder.

## Nasıl öğreniyor?

Kripto sağlayıcısından alınan 7 günlük geçmiş fiyat serisi ve 24 saatlik fiyat değişimi kullanılır. Üç yön stratejisi hesaplanır:

- **Kısa trend:** Son fiyatın önceki yaklaşık 6 veri noktasına göre yönü
- **24s momentum:** 24 saatlik fiyat değişiminin yönü
- **Ters yön:** Aşırı 24 saatlik hareketin tersine dönme ihtimali

Stratejiler +1/0/-1 yön sinyalleri üretir. Başta her biri 1/3 ağırlıktadır. En az 15 dakika sonra **gerçekten yeni zaman damgalı** bir piyasa fiyatı gelirse, önceki tahminin yönüyle karşılaştırılır. Doğru yöndeki stratejilerin ağırlığı artırılır, yanlış olanların ağırlığı azaltılır.

Bu teknik basit *online expert weighting*'dir; yapay zekâ dil modeli, derin öğrenme veya kendi kendini eğiten karmaşık bir ağ değildir. Buradaki doğruluk, **tahmin edilen fiyat yönünün** doğruluğudur; maliyetler sonrası portföy kârlılığıyla aynı şey değildir. Strateji kayıp da üretebilir.

## Otomatik işlem kuralları

- Sadece taze ve pozitif fiyat üzerinden emir; 10 dakikayı aşan eski fiyatlarda işlem reddedilir.
- Alışta strateji puanı en az +0,45; alış tutarı portföyün %12'sini geçmez.
- Minimum %30 sanal nakit, en çok %65 toplam coin değeri, tek coinde en çok %25.
- Günlük en fazla 8 işlem; aynı coinde normalde 30 dakika bekleme.
- Açık pozisyon, maliyet ortalamasına göre yaklaşık %6 düştüğünde veya %8 yükseldiğinde sanal satış tetiklenebilir; limitler ve fiyat ulaşılabilirliği nedeniyle emir her zaman gerçekleşmeyebilir.
- Bot önce çıkışları kontrol eder, sonra alım fırsatlarını değerlendirir; her piyasa yenilemesinde en fazla 1 emir verir.
- Gerçek borsada alım/satım veya para hareketi **asla yapılmaz**.

## Teknik mimari

- `lib/services/learning_bot.dart`: saf sinyal, öğrenme, risk ve emir planlama mantığı
- `lib/services/bot_store.dart`: tarayıcı yerel saklama
- `lib/screens/bot_dashboard.dart`: bot aç/kapat, öğrenme ölçümleri, işlem günlüğü
- `lib/screens/home_screen.dart`: fiyat yenilemesiyle botu tetikler ve mevcut portföy deposundan sanal emir verir
- `test/learning_bot_test.dart`: bot kontrol ve risk testleri

## Dikkat edilmesi gerekenler

- Site **herkese açık**, ancak işlemler aynı tarayıcının yerel verisinde kalır; başka cihazla otomatik eşleşmez.
- Siteyi birden fazla sekmede açıp aynı anda botla işlem yapma; tarayıcı depolaması eşzamanlı işlem kilidi sağlamaz.
- Fiyat API'si 401/403/429 veya ağ hatası verirse işlem gerçekleşmez.
- 'Sıfırla' portföy işlemleri ve öğrenme geçmişini temizler, botu kapatır.
- Ücretsiz sunucu botu artık GitHub Actions üzerinden **periyodik** çalışır; GitHub işi gecikebilir/atlanabilir. Sunucu kasası ve yerel kasa birbirinden ayrıdır. Tek hesapta eşzamanlı gerçek zamanlı işlem veya cihazlar arası otomatik birleştirme henüz yoktur.
