# OpenXR Desteği — Lumina Studio eklentisi (`lumina_plugin_openxr`)

[Lumina](https://github.com/LuminaGame/lumina) oyun motoru ve editörü Lumina Studio için Khronos OpenXR temel
eklentisi. Makinede kurulu OpenXR çalışma zamanını (runtime) bulur, bir Dart Native Assets kancasıyla derlenen küçük
bir yerel köprü üzerinden OpenXR yükleyicisini (loader) açar ve oyunlara ve editöre bir XR uygulamasının yapı
taşlarını verir: izleme uzaylarıyla bir oturum, baş ve kontrolcü bileşenleri olan bir XR origin aktörü, aksiyonlar
için girdi durumu, Filament'in stereoskopik çizimi için stereo projeksiyon matematiği ve gözlük olmadan çalışmak için
benzetimli bir başlık.

*English: [README.md](README.md)*

Üreticiye özgü özellikler bu paketin üzerine kurulur. Meta Quest uzantıları (passthrough, el izleme, uzamsal
çapalar, sahne, yüz ve göz izleme) bu pakete bağımlı olan
[`lumina_plugin_metaxr`](https://github.com/LuminaGame/lumina_plugin_metaxr) içindedir.

## İçindekiler

- [Durum](#durum)
- [Özellikler](#özellikler)
- [Gereksinimler ve platformlar](#gereksinimler-ve-platformlar)
- [Kurulum](#kurulum)
- [Hızlı başlangıç](#hızlı-başlangıç)
- [Kullanım](#kullanım)
- [Editör entegrasyonu](#editör-entegrasyonu)
- [Gözlük olmadan çalışmak](#gözlük-olmadan-çalışmak)
- [Mimari](#mimari)
- [Koordinat sistemleri ve birimler](#koordinat-sistemleri-ve-birimler)
- [Testler](#testler)
- [Sorun giderme](#sorun-giderme)
- [Sınırlamalar ve yol haritası](#sınırlamalar-ve-yol-haritası)
- [Katkı](#katkı)
- [Lisans](#lisans)

## Durum

Sürüm 0.1.0. Eklenti temel katmandır: çalışma zamanı keşfi, yükleyici köprüsü, veri modeli, bileşenler, stereo
matematiği, benzetimli başlık ve editör entegrasyonu hazır ve testli. Yerel köprü henüz bir `XrInstance` /
`XrSession` **oluşturmuyor**, uzay konumu sorgulamıyor ve kareleri compositor'a göndermiyor; bugün "yerel" oturum,
bir çalışma zamanı ve yükleyicinin bulunduğu anlamına gelir. Tablo şu an neyin çalıştığını gösteriyor.

| Alan | Durum |
|---|---|
| Etkin çalışma zamanı keşfi (`XR_RUNTIME_JSON`, Windows kayıt defteri) ve okunur çalışma zamanı adı | tamam |
| OpenXR yükleyici kütüphanesinin açılması (`openxr_loader.dll`, `libopenxr_loader.so[.1]`) | tamam |
| Benzetimli başlık: 6-DoF baş, iki kontrolcü, IPD, göz başına asimetrik FOV, titreşim kaydı | tamam |
| Oturum durum makinesi, izleme orijinleri, OpenXR ↔ Lumina poz dönüşümü | tamam |
| XR origin aktörü, HMD bileşeni (göz konumları), kontrolcü bileşeni (grip/aim, girdiler, titreşim isteği) | tamam |
| Göz başına asimetrik projeksiyon ve görünüm matrisleri; instanced/multiview stereo için Filament `EngineConfig` | tamam |
| Editör menüleri, ayarlar penceresi, durum çubuğu düğmesi, MCP tanılama aracı | tamam |
| Köprü üzerinden `xrCreateInstance` / `xrCreateSession`, olay sorgulama, `xrLocateSpace` / `xrLocateViews` | planlandı |
| Swapchain oluşturma ve kare gönderimi (`xrWaitFrame` / `xrBeginFrame` / `xrEndFrame`) | planlandı |
| Aksiyonların etkileşim profillerine bağlanması (`xrSuggestInteractionProfileBindings`, `xrSyncActions`), gerçek titreşim | planlandı |
| Android (bağımsız Meta Quest) yerel yolu | planlandı (Android bugün benzetimli arka uçla çalışır) |

## Özellikler

### Çalışma zamanı keşfi ve yükleyici köprüsü

- `OpenXrBindings` (tekil örnek `OpenXrBindings.instance`) yerel `openxr_bridge` kütüphanesini açar ve ona sorar:
  - bir OpenXR çalışma zamanı kayıtlı mı (`isNativeRuntimeAvailable`);
  - çalışma zamanı manifest yolu (`activeRuntimePath`) ve okunur adı (`activeRuntimeName`). Köprü manifest yolundan
    Meta Quest / Oculus Link, SteamVR, Windows Mixed Reality, Monado ve Varjo'yu tanır; tanımadığında
    `Active OpenXR Runtime (<yol>)` döner.
- Keşif sırası: `XR_RUNTIME_JSON` ortam değişkeni, ardından (Windows) kayıt defterindeki
  `HKEY_LOCAL_MACHINE\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime` değeri.
- `initialize()` OpenXR yükleyicisini açar: Windows'ta DLL arama yolundan ya da çalışma zamanı manifestinin
  yanından `openxr_loader.dll`; Linux'ta `libopenxr_loader.so` ya da `libopenxr_loader.so.1`. `shutdown()` kapatır.
- Köprü açılamazsa ya da kayıtlı çalışma zamanı yoksa her şey benzetimli arka uca düşer;
  `setForceSimulation(true)` bir çalışma zamanı olsa bile benzetimi zorlar. Hangisinin kullanıldığını `isSimulated`
  söyler.
- `XrResult` OpenXR sonuç kodlarını yansıtır (`isSuccess` / `isFailure`, `fromValue`).

### Oturum ve uzaylar

- `OpenXrSession`: `beginSession()`, `endSession()`, `pollEvents()`, `state` (`OpenXrSessionState`: `idle`,
  `ready`, `synchronized`, `visible`, `focused`, `stopping`, `lossPending`, `exiting`).
- İzleme orijinleri (`OpenXrTrackingOrigin`): `eyeLevel` (oturarak, OpenXR `LOCAL` uzayı), `floorLevel` (ayakta,
  varsayılan) ve `stage` (sınırlı oda ölçeği, `STAGE`). `setTrackingOrigin` uzay ofsetini sıfırlar.
- `OpenXrReferenceSpace` bir orijin ofseti tutar (`setOffset(position, orientation)`).
- `OpenXrSpaceConverter` konum ve yönelimleri OpenXR ile Lumina arasında çevirir
  ([aşağıda](#koordinat-sistemleri-ve-birimler)).
- OpenXR bellek düzeninde FFI yapıları: `XrVector3f`, `XrQuaternionf`, `XrPosef`, `XrFovf`, `XrView`.

### Bileşenler

| Sınıf | Tür | Ne yapar |
|---|---|---|
| `LuminaXROriginActor` | `LuminaActor` | Dünyadaki oyun alanı. `hmdComponent`, `leftController` ve `rightController`'ı oluşturup köküne bağlar; `trackingOrigin`; `recenter()` başı orijine sıfırlar. |
| `LuminaXRHMDComponent` | `LuminaSceneComponent` | Baş. `updatePoseFromOpenXr(position, orientation)` OpenXR pozu, `updatePoseLumina(location, rotation)` Lumina pozu alır; `interPupillaryDistance` (metre, varsayılan 0.064); IPD'den türetilen `leftEyeLocation` / `rightEyeLocation`. |
| `LuminaXRControllerComponent` | `LuminaSceneComponent` | Bir `LuminaXRHand` için hareket kontrolcüsü. `updatePoseFromOpenXr` ile grip pozu (`location` / `rotation`) ve aim pozu (`aimLocation` / `aimRotation`); `trigger`, `grip` (eksen), `thumbstick` (2B), `primaryButton`, `secondaryButton`, `menuButton`; `playHapticPulse(amplitude, durationMicroseconds, frequencyHz)` isteği `lastHapticPulse`'a kaydeder. |
| `LuminaXRHand` | enum | `left`, `right` (`isLeft`, `isRight`). |

### Girdi

- `OpenXrButtonState` (`isPressed`, `isTouched`, `justPressed`, `justReleased`), `OpenXrAxisState` (0..1,
  `delta` ile), `OpenXrVector2State` (eksen başına −1..1), `OpenXrHapticFeedback`, `OpenXrActionType`.
- `OpenXrActionSet` iki el için standart kontrolcü aksiyonlarını toplar (tetikler, grip'ler, analog çubuklar,
  A/B/X/Y, menü düğmeleri).
- `OpenXrInteractionProfiles` standart profilleri adlandırır: Khronos simple controller, Oculus Touch, Valve Index,
  HTC Vive, Microsoft motion controller.

### Stereo çizim

- `OpenXrStereoView`: bir gözün pozu ve OpenXR `XrFovf`'in dört FOV açısı; `createProjectionMatrix(nearPlane,
  farPlane)` asimetrik (eksen dışı) perspektif projeksiyonu, `createViewMatrix()` göz dönüşümünün tersini üretir.
- `OpenXrFilamentBridge`: stereo tekniğini seçer (`OpenXrStereoMode.instanced` (varsayılan), `multiview`,
  `separateViews`), bunu Filament'in `StereoscopicType`'ına eşler; `createEngineConfig()` iki stereoskopik gözlü bir
  `flutter_filament` `EngineConfig` döner. `updateEyeViews(left:, right:)` güncel göz görünümlerini saklar.
- `OpenXrSwapchainDescriptor` / `OpenXrSwapchainFormat`: bir stereo swapchain'in parametreleri (boyut, örnek sayısı,
  sRGB/UNORM renk ya da derinlik formatı, doku dizisi için `arraySize` 2).

### Benzetimli başlık

`SimulatedOpenXrBackend` (`OpenXrBindings.instance.simulator` ile erişilir) eksiksiz bir yedek çalışma zamanıdır:
sistem adı "Lumina Virtual OpenXR HMD", göz başına 2064 × 2208, 90 Hz, IPD 64 mm, baş 1,7 m'de, iki kontrolcü önde bel
hizasında. Asimetrik FOV'lu göz görünümleri verir (`getLeftEyeView()`, `getRightEyeView()`), baş bakış açılarını
(`setHeadLookAngles(yaw, pitch)`), kontrolcü pozlarını (`setControllerPose`) ve girdilerini
(`setControllerInputs`: tetik, grip, analog çubuk, birincil/ikincil düğmeler) alır ve titreşimleri kaydeder
(`applyHapticFeedback`).

## Gereksinimler ve platformlar

- Dart SDK `^3.12.0` ile Flutter ve Native Assets kancasının bulabileceği bir C/C++ araç zinciri: Windows'ta C++ iş
  yüküyle Visual Studio 2022, Linux'ta clang ya da gcc.
- `pubspec.yaml`'da commit ile sabitlenmiş Lumina paketleri (`lumina`, `lumina_editor_api`, `flutter_filament`) ve
  `flutter_filament`'in bağladığı hazır Filament derlemesi (bkz.
  [Lumina kurulum rehberi](https://github.com/LuminaGame/lumina/blob/main/docs/tr/getting-started/setup.md)).
- Gerçek bir başlık için: kendini etkin çalışma zamanı olarak kaydeden kurulu bir OpenXR çalışma zamanı (Meta Quest
  Link, SteamVR, Windows Mixed Reality, Varjo, Monado, …) ve kütüphane yolunda OpenXR yükleyicisi. OpenXR SDK'nın
  hiçbir parçası pakete dahil değildir; yükleyici çalışma zamanından ya da sistemden gelir.

| Platform | Çalışma zamanı keşfi | Yükleyici | Notlar |
|---|---|---|---|
| Windows (PC VR) | `XR_RUNTIME_JSON`, kayıt defteri | `openxr_loader.dll` (arama yolu ya da manifestin yanı) | Ana hedef. |
| Linux | `XR_RUNTIME_JSON` | `libopenxr_loader.so`, `.so.1` | `XR_RUNTIME_JSON`'u ayarlayın (ör. Monado'nun manifesti); varsayılan `/etc/xdg/openxr/1/active_runtime.json` henüz okunmuyor. |
| Android (Meta Quest) | — | — | Köprü kütüphanesi Android'de açılmıyor; benzetimli arka uç kullanılır. |
| macOS | — | — | OpenXR çalışma zamanı yok; yalnızca benzetimli arka uç. |

## Kurulum

### Lumina Studio eklentisi olarak

Paket kendi manifestini taşır: `lumina_plugin_openxr.lmplugin` (kategori *Virtual Reality*, editör modülü
`LuminaPluginOpenxrPlugin`). Lumina Studio `<proje>/plugins/` klasörünü, kullanıcı eklenti klasörünü (Linux'ta
`~/.local/share/lumina/plugins/`, Windows'ta `%LOCALAPPDATA%\Lumina\plugins`) ve motorun yerleşik eklentilerini
tarar.

1. Bu depoyu klonlayın ve bu klasörlerden birine bağlayın ya da kopyalayın (veya **Plugins → Plugin Manager →
   Import from Folder** kullanın).
2. Plugin Manager'da **OpenXR Support**'u etkinleştirin ve editör isterse yeniden başlatın.

Keşif, etkinleştirme ve kod eklentilerinin editöre nasıl derlendiği için
[Editör eklentileri](https://github.com/LuminaGame/lumina/blob/main/docs/tr/plugins/index.md) sayfasına bakın.

### Bir oyunun ya da başka bir eklentinin bağımlılığı olarak

```yaml
dependencies:
  lumina_plugin_openxr:
    git:
      url: https://github.com/LuminaGame/lumina_plugin_openxr.git
      ref: <commit sha>
```

Ardından `flutter pub get`. Her şey tek kütüphaneden içe aktarılır:

```dart
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';
```

### Yerel köprü

`hook/build.dart`, ilk `flutter run` / `flutter test` / `flutter build`'de `src/openxr_bridge_c.cpp`'yi
`package:native_toolchain_c` ile `openxr_bridge` kod varlığına derler: C++17; Windows'ta `Advapi32` (kayıt defteri
erişimi), Linux'ta `libdl` ile bağlanır. Derleme sırasında OpenXR başlık dosyalarına ya da kütüphanelerine ihtiyaç
duymaz; yükleyici çalışma anında açılır. Kütüphane açılamazsa eklenti benzetimli arka uçla çalışmaya devam eder.

### Kardeş checkout'lara karşı yerel geliştirme

`pubspec.yaml` GitHub'daki Lumina depolarını gösterir. Bu deponun yanındaki yerel checkout'lara (`../lumina`,
`../tools`) karşı derlemek için `lumina`, `lumina_editor_api`, `flutter_filament` ve tools paketleri için
`dependency_overrides:` içeren, gitignore'lu bir `pubspec_overrides.yaml` oluşturun ve paylaşılan Filament
derlemesini `filament` adıyla bağlayın (`pubspec.yaml`'daki `hooks: user_defines:` onu oradan okur).

## Hızlı başlangıç

```dart
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

void startXr() {
  final xr = OpenXrBindings.instance;
  print('Runtime: ${xr.activeRuntimeName} (simulated: ${xr.isSimulated})');

  final session = OpenXrSession()..setTrackingOrigin(OpenXrTrackingOrigin.floorLevel);
  final result = session.beginSession();
  if (result.isFailure) {
    print('OpenXR session failed: $result');
    return;
  }

  // Oyun alanı: baş + iki kontrolcü, aktörün köküne bağlı.
  final origin = LuminaXROriginActor(trackingOrigin: session.trackingOrigin);
  // `origin`'i dünyanıza diğer LuminaActor'lar gibi ekleyin.
}
```

## Kullanım

### Baş ve kontrolcüleri her karede sürmek

Bileşenler OpenXR pozlarını (metre, Y yukarı) alır ve Lumina dönüşümlerini (santimetre, Z yukarı) saklar. Benzetimli
arka uçla:

```dart
final sim = OpenXrBindings.instance.simulator;

void tick(LuminaXROriginActor origin, OpenXrSession session) {
  session.pollEvents();

  origin.hmdComponent.updatePoseFromOpenXr(sim.headPosition, sim.headOrientation);
  origin.leftController.updatePoseFromOpenXr(
    openXrGripPos: sim.leftGripPosition,
    openXrGripRot: sim.leftGripOrientation,
  );
  origin.rightController
    ..updatePoseFromOpenXr(
      openXrGripPos: sim.rightGripPosition,
      openXrGripRot: sim.rightGripOrientation,
    )
    ..trigger.update(sim.rightTrigger)
    ..primaryButton.update(sim.rightPrimaryButton);

  if (origin.rightController.primaryButton.justPressed) {
    origin.rightController.playHapticPulse(amplitude: 0.6, durationMicroseconds: 20000);
  }
}
```

### Filament için göz başına projeksiyon

```dart
final bridge = OpenXrFilamentBridge(stereoMode: OpenXrStereoMode.multiview)..isStereoEnabled = true;
final engineConfig = bridge.createEngineConfig(); // stereoscopicEyeCount: 2, StereoscopicType.multiview

final l = OpenXrBindings.instance.simulator.getLeftEyeView();
final left = OpenXrStereoView(
  eyePosition: l.position,
  eyeOrientation: l.orientation,
  angleLeft: l.fovLeft,
  angleRight: l.fovRight,
  angleUp: l.fovUp,
  angleDown: l.fovDown,
);
final projection = left.createProjectionMatrix(nearPlane: 0.05, farPlane: 1000.0);
final view = left.createViewMatrix();
```

### Pozları kendiniz çevirmek

```dart
final luminaLocation = OpenXrSpaceConverter.openXrToLuminaPosition(openXrPosition); // cm, Z yukarı
final luminaRotation = OpenXrSpaceConverter.openXrToLuminaRotation(openXrOrientation);
final openXrPosition2 = OpenXrSpaceConverter.luminaToOpenXrPosition(luminaLocation); // m, Y yukarı
```

## Editör entegrasyonu

Eklenti etkinleştirildiğinde şunları ekler:

| Yer | Öğe | Ne yapar |
|---|---|---|
| **Plugins → OpenXR → Check Runtime** | pencere | Etkin çalışma zamanını ve manifest yolunu ya da benzetimli başlığın kullanıldığını gösterir. |
| **Plugins → OpenXR → Toggle VR Preview** | komut | Eklentinin OpenXR oturumunu başlatır ya da bitirir ve Output Log'a yazar (kaynak `OpenXR`). |
| **Plugins → OpenXR → OpenXR Settings** | pencere | Çalışma zamanı ve manifest, **Force Simulated Runtime** anahtarı, izleme orijini (eyeLevel / floorLevel / stage) ve stereo modu seçimi. |
| **Plugins → OpenXR → About OpenXR Support** | pencere | Sürüm ve özet. |
| Durum çubuğu (sağ) | **XR Status** düğmesi | Çalışma zamanı tanılamasını açar. |
| MCP | `lumina_plugin_openxr.get_status` (salt okunur) | `active_runtime`, `manifest_path`, `is_simulated`, `session_state`, `tracking_origin`, `vr_preview_active` döner. |

`OpenXrStatusBadge` (yerel / benzetimli / çevrimdışı gösteren rozet) ve `OpenXrSettingsView` dışa aktarılan
widget'lardır; bir oyunun kendi arayüzü ya da başka bir eklenti bunları gömebilir. MCP aracına Lumina Studio'nun
yerleşik MCP sunucusuna bağlı herhangi bir MCP istemcisinden ulaşılır.

## Gözlük olmadan çalışmak

Eklentideki hiçbir şey donanım gerektirmez. Kayıtlı bir çalışma zamanı yokken (ya da **Force Simulated Runtime**
açıkken) `OpenXrBindings` her şeyi `SimulatedOpenXrBackend`'e yönlendirir: oturumlar başlar ve `focused` durumuna
gelir, baş ve kontrolcülerin makul pozları olur, girdiler ve titreşimler testlerden ya da araçlardan betiklenebilir.
`lumina_plugin_metaxr` bunun üzerine benzetimli el hareketlerini süren bir editör paneli ekler.

## Mimari

```
lib/
  lumina_plugin_openxr.dart          genel kütüphane (aşağıdakilerin hepsini dışa aktarır)
  src/lumina_plugin_openxr_plugin.dart   LuminaEditorPlugin: menüler, durum çubuğu düğmesi, MCP aracı
  src/ffi/        OpenXrBindings (yerel köprü + benzetim anahtarı), OpenXR türleri/yapıları, SimulatedOpenXrBackend
  src/session/    OpenXrSession, OpenXrReferenceSpace, OpenXrSpaceConverter
  src/input/      aksiyon kümesi, düğme/eksen/vector2 durumu, titreşim, etkileşim profili yolları
  src/components/ LuminaXROriginActor, LuminaXRHMDComponent, LuminaXRControllerComponent, LuminaXRHand
  src/render/     OpenXrStereoView, OpenXrFilamentBridge, OpenXrSwapchainDescriptor
  src/ui/         OpenXrSettingsView, OpenXrStatusBadge (shadcn_flutter)
hook/build.dart   köprüyü derleyen Native Assets kancası
src/              openxr_bridge_c.h / .cpp (C API, FFI_PLUGIN_EXPORT)
```

- **Dart ↔ yerel.** Köprü beş C fonksiyonu dışa aktarır: `openxr_bridge_is_runtime_available`,
  `openxr_bridge_get_active_runtime_path`, `openxr_bridge_get_active_runtime_name`, `openxr_bridge_initialize`
  (başarıda 0) ve `openxr_bridge_shutdown`. `OpenXrBindings` bunları `dart:ffi` ile bulur, sonuçları `XrResult` ve
  Dart dizgilerine çevirir. Her çağrı korumalıdır; bir hata `package:logging` (logger `OpenXrBindings`) ile
  kaydedilir ve benzetime düşülür.
- **İş parçacıkları.** Tüm çağrılar eşzamanlıdır ve dünyanın sahibi olan Dart isolate'inden yapılır (Lumina
  Studio'da UI isolate'i). Köprü durumunu süreç genelindeki statik değişkenlerde tutar; tek bir isolate'ten çağırın.
- **Kare döngüsü.** Döngü oyunun (ya da aracın) elindedir: `session.pollEvents()`, pozları okuyun (bugün
  benzetimden), bileşenlere verin, göz görünümlerini kurun ve çiziciye verin. Instance/oturum oluşturma geldiğinde
  poz ve kare zamanlamasını köprü üstlenecek.
- **Stereo yolu.** OpenXR her göz için bir poz ve dört FOV yarı açısı verir; `OpenXrStereoView` bunları eksen dışı
  projeksiyona ve görünüm matrisine çevirir; `OpenXrFilamentBridge` Filament'i iki gözlü instanced ya da multiview
  çizim için yapılandırır (`OpenXrSwapchainDescriptor.arraySize` ile uyumlu, 2 katmanlı doku dizisine tek geçiş) ya da
  `separateViews` ile göz başına sıradan bir geçiş yapılır.

## Koordinat sistemleri ve birimler

| | Birim | Eksenler |
|---|---|---|
| OpenXR | metre | sağ el kuralı, X sağ, Y yukarı, −Z ileri |
| Lumina (saklanan dönüşümler) | santimetre (bir dünya birimi = 1 cm) | Z yukarı |

`OpenXrSpaceConverter`, OpenXR `(x, y, z)` metreyi `(−z, x, y) × 100` santimetreye çevirir — X ileri, Y sağ, Z
yukarı — ve `luminaToOpenXrPosition` ile geri; `openXrToLuminaRotation` aynı taban değişimini yönelimlere uygular.
HMD bileşeni aynı çerçevede çalışır (gözleri yerleştirirken +Y sağdır) ve IPD'yi metre olarak tutar. Benzetim ve
stereo matematiği, çalışma zamanının bildirdiği gibi OpenXR metresinde kalır.

## Testler

Birim testleri benzetimli arka uçta çalışır; başlık ya da GPU gerektirmez:

```bash
flutter test test/openxr_loader_and_types_test.dart
flutter test test/openxr_session_and_spaces_test.dart
flutter test test/openxr_stereo_render_test.dart
flutter test test/xr_components_test.dart
flutter test test/openxr_editor_integration_test.dart
flutter analyze
```

Sonuç kodlarını ve yapı düzenlerini, benzetime düşmeyi, oturum durumlarını ve izleme orijinlerini, koordinat
dönüşümünü, girdi durumlarını, projeksiyon matrisini (sonlu değerler), Filament stereo eşlemesini, origin aktörünün
bileşenlerini ve editör kaydını (bir host bağlamına karşı menüler ve MCP aracı) kapsarlar.

## Sorun giderme

- **Başlık bağlı olduğu halde "Lumina Simulated HMD".** Çalışma zamanının etkin OpenXR çalışma zamanı olarak
  ayarlandığını denetleyin (Meta Quest Link uygulamasında, SteamVR ayarlarında, …). Linux'ta `XR_RUNTIME_JSON`'u
  çalışma zamanının manifestine ayarlayın. **Force Simulated Runtime**'ın kapalı olduğundan emin olun.
  **Plugins → OpenXR → Check Runtime** köprünün ne bulduğunu gösterir.
- **`openxr_bridge_initialize` başarısız (initialization failed).** Yükleyici bulunamadı: `openxr_loader.dll`'i DLL
  arama yoluna (ya da çalışma zamanı manifestinin yanına) koyun ya da Linux'ta sistemin OpenXR yükleyici paketini
  kurun (`libopenxr-loader1` ya da eşdeğeri).
- **Kanca derlenmiyor.** C++ araç zincirini kurun (Windows'ta Visual Studio 2022 C++ iş yükü, Linux'ta clang/gcc) ve
  `flutter clean` çalıştırın.
- **Yanlış çalışma zamanı adı.** Ad manifest yolundan tahmin edilir; tanınmayan bir çalışma zamanı yoluyla
  bildirilir, bu davranışı etkilemez.

## Sınırlamalar ve yol haritası

- Köprü üzerinden henüz `XrInstance`, `XrSession`, uzay konumu, swapchain ya da kare gönderimi yok; çalışma zamanı
  olan bir makinede oturum yükleyici açıldığında `focused` bildirir, pozlar sizin kodunuzdan ya da benzetimden gelir.
- `OpenXrActionSet.sync()` henüz çalışma zamanını okumuyor; kontrolcü durumlarını çağıran doldurur.
  `playHapticPulse` isteği (`lastHapticPulse`) kaydeder ama bir cihaza göndermez.
- Ayarlar penceresinde seçilen stereo modu henüz eklentinin `OpenXrFilamentBridge`'ine aktarılmıyor.
- Durum çubuğu düğmesinin etiketi sabit; canlı `OpenXrStatusBadge` widget'ı gömmek için hazır.
- `OpenXrSpaceConverter` kendi ileri eksenini (+X) kullanıyor; motorun yazım çerçevesiyle (`LuminaAxes`) hizalanması
  planlandı.
- Android / bağımsız Meta Quest derlemeleri, köprü Android için derlenip yüklenene kadar benzetimli arka ucu kullanır.

Sıradakiler: gerekli uzantılarla instance ve oturum oluşturma, bileşenleri besleyen `xrLocateViews` /
`xrLocateSpace`, Filament ile paylaşılan swapchain görüntüleri, gerçek titreşimle etkileşim profili başına aksiyon
bağlamaları ve Android yükleyici yolu.

## Katkı

Issue ve pull request'ler memnuniyetle karşılanır. Analizörü temiz tutun (`flutter analyze`), yeni davranış için bir
birim testi ekleyin (testler benzetimli arka ucu kullanır; motorun sahtesi yazılmaz) ve iki README'yi (İngilizce ve
Türkçe) birlikte güncel tutun. Arayüz, Lumina Studio'nun her yerinde olduğu gibi yalnızca `shadcn_flutter`
widget'ları kullanır.

## Lisans

MIT — bkz. [LICENSE](LICENSE).

Bu depo üçüncü taraf kaynak kodu ya da ikili dosya içermez. Çalışma anında makinede zaten kurulu olan OpenXR
yükleyicisini ve çalışma zamanını açar (Khronos OpenXR yükleyicisi Apache-2.0'dır; çalışma zamanlarının kendi
lisansları vardır). OpenXR™, The Khronos Group Inc.'in ticari markasıdır.
