# Ücretsiz DEX Radar — veri doğruluğu ve kapsama sınırları

Kaynak: https://api.geckoterminal.com/api/v2
Bu servis anahtar veya abonelik olmadan herkese açık havuz/işlem sorguları
sağlar. Üçüncü taraf API, kısıtlama veya 429 nedeniyle çalışmayabilir.

Bot GitHub Actions üzerinde, tek sunucu state.json dosyasına bağımsız
freeDexRadar alanı olarak yazar. Son kontrol başarılı/başarısız fark etmeksizin
12 dakikadan sık tekrar edilmez. Kapsam tüm Solana/Base ağı değildir:
her ağın ilk trend sayfasından, likiditesi en az 200.000 USD olan ve 1 saatlik
fiyat değişimi %30'dan fazla artmamış en fazla iki havuz seçilir.
Her havuzun public trades yanıtından en çok 300 kayıt incelenir.
Son 20 dakikadaki, en az 100 USD hacimli, anomalik diye işaretlenmemiş
buy ve sell kayıtları, tx_hash ve tx_from_address bazında gözlemlenir.

Aynı ağ/token adresinde 20 dakika içinde birbirinden farklı üç işlem
göndericisi varsa THREE_SENDERS_UNVERIFIED araştırma kümesi kaydedilir.
Aynı işlem kimliği bir kez sayılır. 24 saat boyunca aynı token tekrar
kümelenmez. Kümelerin 24 saatlik geçmişi ve örneklemde gözlenen en fazla
15 gönderici adresi uygulamanın Radar ekranında gösterilir.

ÖNEMLİ: Bu veri bizzat Solana/Base zinciri üzerinden bağımsız teyit
edilmez, üçüncü tarafın işlem bildirimidir. tx_from_address her zaman
hakiki alıcı veya ekonomik faydalanıcı olmayabilir. Üç adres, üç bağımsız
kişi demek değildir. 30 günlük 750.000 USD kâr, %65 kazanma oranı, fon
bağımsızlığı, token LP kilidi, mint/freeze yetkisi veya kötü niyetli
sözleşme kontrolleri bu ücretsiz tarama ile ispatlanmaz. Bu nedenle
Akıllı Para onaylı alım sinyali değildir ve otomatik SPOT, SHORT veya
DEX paper alım-satımına bağlanmaz. Var olan 650 TL cüzdan korunur.

Önceki smartMoney katmanı, harici güvenilir veri kaynağı bağlanırsa
bunun üstünde doğrulanmış cüzdan filtrelerini ayrıca uygular. Şu an
GeckoTerminal kaynağı o katmanın eksik şartlarını otomatik tamamlamaz.

Test: python3 -m unittest discover -s backend/tests -v
