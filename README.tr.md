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
- [Kendi sürecinde çalışır](#kendi-sürecinde-çalışır)
- [Gözlük olmadan çalışmak](#gözlük-olmadan-çalışmak)
- [Mimari](#mimari)
- [Kare döngüsü](#kare-döngüsü)
- [Koordinat sistemleri ve birimler](#koordinat-sistemleri-ve-birimler)
- [Testler](#testler)
- [Sorun giderme](#sorun-giderme)
- [Sınırlamalar ve yol haritası](#sınırlamalar-ve-yol-haritası)
- [Katkı](#katkı)
- [Lisans](#lisans)

## Durum

Sürüm 0.1.0. Eklenti temel katmandır: çalışma zamanı keşfi, yükleyici köprüsü, veri modeli, bileşenler, stereo
matematiği, benzetimli başlık ve editör entegrasyonu hazır ve testli. Yerel köprü `XrInstance`'ı, Vulkan cihazını
(`XR_KHR_vulkan_enable2`) ve `XrSession`'ı oluşturuyor, çalışma zamanının oturum olaylarını izliyor, kare döngüsünü
yerel bir iş parçacığında çalıştırıyor ve uzayları ile görünümleri konumluyor; bir Meta Quest 3S üzerinde çalışıyor.
Tablo şu an neyin çalıştığını gösteriyor.

| Alan | Durum |
|---|---|
| Etkin çalışma zamanı keşfi (`XR_RUNTIME_JSON`, Windows kayıt defteri) ve okunur çalışma zamanı adı | tamam |
| OpenXR yükleyici kütüphanesinin açılması (`openxr_loader.dll`, `libopenxr_loader.so[.1]`) | tamam |
| Benzetimli başlık: 6-DoF baş, iki kontrolcü, IPD, göz başına asimetrik FOV, titreşim kaydı | tamam |
| Oturum durum makinesi, izleme orijinleri, OpenXR ↔ Lumina poz dönüşümü | tamam |
| XR origin aktörü, HMD bileşeni (göz konumları), kontrolcü bileşeni (grip/aim, girdiler, titreşim isteği) | tamam |
| Göz başına asimetrik projeksiyon ve görünüm matrisleri; instanced/multiview stereo için Filament `EngineConfig` | tamam |
| Editör menüleri, OpenXR paneli (bir editör paneli Widget Blueprint'i), durum çubuğu düğmesi, MCP tanılama aracı | tamam |
| `xrCreateInstance` / `xrCreateSession`, `XR_KHR_vulkan_enable2` ile Vulkan cihazı, olay sorgulama ve olaylarla ilerleyen oturum durum makinesi, `xrLocateSpace` / `xrLocateViews` | tamam (Quest 3S: 72 Hz'de FOCUSED) |
| Kare döngüsü (yerel bir zamanlayıcı iş parçacığında `xrWaitFrame`, bir renderer bağlanana kadar boş kareler) | tamam |
| Çalışma zamanının Vulkan cihazında swapchain, iki gözü (multiview) ona render eden Filament, projeksiyon katmanıyla kare gönderimi; `OpenXrFrameLoop`, `LuminaXRWorldDriver` | tamam (Quest 3S: 72 Hz, < %0,1 geç kare) |
| Etkileşim profili başına bağlanan aksiyonlar (Touch Plus, Touch, simple controller), her karede `xrSyncActions`, öngörülen gösterim zamanında grip / aim pozları, çalışma zamanında titreşim; `OpenXrInputSystem`, XR tuşları, Blueprint düğümleri | tamam (Quest 3S: aksiyonlar bağlı, pozlar 72 Hz'de izleniyor) |
| Android (bağımsız Meta Quest) yerel yolu: Maven Central'dan Khronos yükleyicisi, Kotlin parçasının (`OpenXrPlugin`) ilettiği activity | tamam |
| `package:lumina_plugin_openxr/runtime.dart`: bir oyunun içe aktardığı, editör kodu içermeyen kütüphane | tamam |

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
| `LuminaXRControllerComponent` | `LuminaSceneComponent` | Bir `LuminaXRHand` için hareket kontrolcüsü. `updatePoseFromOpenXr` ile grip pozu (`location` / `rotation`) ve aim pozu (`aimLocation` / `aimRotation`); `gripAxis`, `triggerAxis` (histerezisli), `thumbstick` (2B), düğmeler, `isTracked`; `playHapticPulse(amplitude:, seconds:, frequencyHz:)` çalışma zamanına gider. Bir `LuminaGrabber`. |
| `LuminaXRHand` | enum | `left`, `right` (`isLeft`, `isRight`). |

### Girdi

- **Aksiyon kümesi ve bağlamalar.** `lib/src/input/bindings.json` (`tool/embed_bindings.dart` gömer;
  `OpenXrInputBindings.defaults` olarak okunur) `gameplay` aksiyon kümesini tanımlar: `grip_pose`, `aim_pose`, `grip`
  (sıkma değeri), `trigger`, `trigger_touch`, `thumbstick`, `thumbstick_click`, `primary` (X / A), `secondary` (Y / B),
  `menu`, `haptic`; ve bağlamalarını: `/interaction_profiles/meta/touch_controller_plus` (Quest 3 / 3S; yalnızca
  instance'ta `XR_META_touch_controller_plus` varsa önerilir, oturum bunu ister), `oculus/touch_controller` (her
  çalışma zamanının bildiği yedek) ve `khr/simple_controller` (`select/click` → `trigger`). Çalışma zamanının
  reddettiği profil atlanır.
- **`OpenXrInputSystem`** (bir `LuminaWorldSubsystem`): `setup()` aksiyonları oluşturur, bağlamaları önerir, bağlar
  ve grip ile aim aksiyon uzaylarını oluşturur; `sync(displayTime)` (`OpenXrFrameLoop.input` dünya tick'inden önce
  çağırır) `xrSyncActions` çalıştırır, iki pozu karenin öngörülen gösterim zamanında konumlar ve kontrolcü
  bileşenlerine yazar; `attachTo(world)` onu kaydeder, böylece XR tuşları dünyanın `LuminaInputSubsystem`'ine ulaşır
  ve Blueprint düğümleri onu bulur. `refreshInteractionProfiles()` (`OpenXrSession.onInteractionProfileChanged`'e
  bağlayın) her elin kullandığı profili günlüğe yazar.
- **`LuminaXRControllerComponent`**: grip pozu (`location` / `rotation`, çalışma zamanı eksenleri, cm), aim pozu
  (`aimLocation` / `aimRotation`, `aimWorldLocation` / `aimWorldRotation`), `gripAxis` / `triggerAxis` (0..1,
  histerezisli: 0,7 üstünde basılı, 0,3 altında bırakılmış, `justPressed` / `justReleased`), `thumbstick`,
  `primaryButton`, `secondaryButton`, `menuButton`, `thumbstickButton`, `triggerTouched`, `isTracked` (izlenmeyen
  kontrolcü son pozunu korur). `playHapticPulse(amplitude:, seconds:, frequencyHz:)` çalışma zamanına gider
  (`xrApplyHapticFeedback`; 0 sn en kısa darbe, 0 Hz frekansı çalışma zamanına bırakır). Bir `LuminaGrabber`'dır
  (`id` `left` / `right`, birim ölçekli `worldTransform`, `grip`, aim pozu boyunca `ray`, `pulse`); böylece
  `LuminaPoseGrabInteractor` onu fare gibi kullanır.
- **Proje girdisi.** XR tuşları (`XR_Left_Grip`, `XR_Left_Trigger`, `XR_Left_Thumbstick_X` / `_Y`,
  `XR_Left_Thumbstick_Click`, `XR_Left_X`, `XR_Left_Y`, `XR_Left_Menu`, `XR_Right_Grip`, `XR_Right_Trigger`,
  `XR_Right_Thumbstick_X` / `_Y`, `XR_Right_Thumbstick_Click`, `XR_Right_A`, `XR_Right_B`) birer `LuminaKey`'dir;
  Project Settings bunları *XR Controllers* altında listeler, bir girdi aksiyonu onları herhangi bir tuş gibi bağlar.
  Grip, tetik ve analog çubuk eksenleri analog, düğmeler dijitaldir.
- **Blueprint düğümleri** (*XR | Controllers* kategorisi; `attachTo` ya da `OpenXrBlueprintNodes.register()` kaydeder):
  Get Controller Grip Transform, Get Controller Aim Transform (dünya, yazım eksenleri), Get Grip Value, Get Trigger
  Value, Is Controller Tracked, Play Haptic Pulse (el, genlik, saniye, frekans). El `Left` ya da `Right`'tır.
- **`OpenXrControllerVisuals`**: bir Filament sahnesi için hata ayıklama görselleri: her grip'te rengi grip ve tetiği
  izleyen bir küp, her aim pozu boyunca bir ışın.
- `OpenXrButtonState`, `OpenXrAxisState`, `OpenXrVector2State`, `OpenXrHapticFeedback`, `OpenXrActionType`;
  `OpenXrInteractionProfiles` profilleri adlandırır.

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
| Android (Meta Quest) | çalışma zamanı aracısı | Khronos yükleyici AAR'ı (Maven Central, derlemede indirilir) | Quest 3S'te doğrulandı: oturum, 72 Hz kare döngüsü, kontrolcüler. |
| macOS | — | — | OpenXR çalışma zamanı yok; yalnızca benzetimli arka uç. |

## Kurulum

### Lumina Studio eklentisi olarak

Paket kendi manifestini taşır: `lumina_plugin_openxr.lmplugin` (kategori *Virtual Reality*, `process_class`'ı
`LuminaPluginOpenxrProcess` olan tek bir modül, `content/` içindeki panel için `"can_contain_content": true`). Lumina
Studio `<proje>/plugins/` klasörünü, kullanıcı eklenti klasörünü (Linux'ta
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

Yalnızca düz XR türlerine (`LuminaXRHand`, `OpenXrActionType`, aksiyon ve girdi durumu sınıfları,
`OpenXrInteractionProfiles`) ihtiyaç duyan kod bunun yerine `package:lumina_plugin_openxr/xr_types.dart`'ı içe
aktarabilir: ne `dart:ffi`'ye ne de OpenXR köprüsüne ulaşır. Ana kütüphane aynı türleri dışa aktarır.

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

Bunu `OpenXrFrameLoop` yapar: her karede görünümler rig'e gider (`LuminaXRWorldDriver`), girdi sistemi kontrolcüleri
karenin öngörülen gösterim zamanında eşitler, sonra dünya tick'lenir. Kare döngüsü olmadan (bir test, bir araç)
`OpenXrInputSystem.sync`'i kendiniz çağırın. Benzetimli arka uçla:

```dart
final sim = OpenXrBindings.instance.simulator..initialize();
final origin = LuminaXROriginActor();
final input = OpenXrInputSystem.forOrigin(sim.input, origin)..setup();
input.attachTo(world); // XR tuşları dünyanın girdisine, Blueprint XR düğümleri

sim.setControllerInputs(isLeft: false, trigger: 0.9, primaryButton: true);
input.sync(displayTimeNs);

final right = origin.rightController;
if (right.triggerAxis.justPressed) right.playHapticPulse(amplitude: 0.6, seconds: 0.05);
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
| **Plugins → OpenXR → OpenXR Panel** | **OpenXR** panelini açar | Panelin kendi menü öğesi (`menuPath`'i). |
| **Plugins → OpenXR → Check Runtime** | **OpenXR** panelini açar | Etkin çalışma zamanını ve manifest yolunu ya da benzetimli başlığın kullanıldığını gösterir. |
| **Plugins → OpenXR → Toggle VR Preview** | komut, çalışırken işaretli | Eklentinin OpenXR oturumunu başlatır ya da bitirir ve Output Log'a yazar (kaynak `OpenXR`). |
| **Plugins → OpenXR → OpenXR Settings** | **OpenXR** panelini açar | Çalışma zamanı ve manifest, **Force Simulated Runtime** anahtarı, izleme orijini (eyeLevel / floorLevel / stage) ve stereo modu seçimi. |
| **Plugins → OpenXR → About OpenXR Support** | **OpenXR** panelini açar | Sürüm ve özet (panelin kapalı About bölümü). |
| Durum çubuğu (sağ) | **XR** düğmesi | Etkin çalışma zamanını canlı gösterir (`XR (Sim)` ya da `XR: <çalışma zamanı>`; VR önizlemesi çalışırken yeşil ve noktalı); tıklayınca Check Runtime, Toggle VR Preview ve OpenXR Settings içeren bir menü açar. |
| **OpenXR** paneli (sağ yuva) | editör paneli Widget Blueprint'i | Çalışma zamanı, manifest ve türü; Force Simulated Runtime; izleme orijini ve stereo modu; oturum durumu ve Start / Stop VR Preview düğmesi; About (kapalı). Değişikliği hangi menü, düğme ya da MCP istemcisi yapmış olursa olsun güncel kalır. |
| MCP | `lumina_plugin_openxr.get_status` (salt okunur) | `active_runtime`, `manifest_path`, `is_simulated`, `simulation_forced`, `native_runtime_available`, `session_state`, `tracking_origin`, `stereo_mode`, `vr_preview_active` döner. |

MCP aracına Lumina Studio'nun yerleşik MCP sunucusuna bağlı herhangi bir MCP istemcisinden ulaşılır.

### OpenXR paneli bir varlıktır

Panel `content/Editor/EPW_OpenXR.lmas`'tır: bir editör paneli Widget Blueprint'i (`editorPanel` bloğu olan bir Widget
Blueprint: başlık *OpenXR*, simge `glasses`, yuva `right`, menü yolu `Plugins/OpenXR/OpenXR Panel`, yalnızca `process`
yeteneği). Onu hiçbir Dart kodu kurmaz: editör onu etkin eklentinin `content/` klasöründe bulur, grafiğini kendi
Blueprint VM'ine derler ve yuvaya yerleştirir; editör derlemesi gerekmez. Editör widget setiyle yerleşir (dört Editor
Section: Active Runtime, Tracking & Stereoscopic, VR Preview, kapalı About OpenXR Support) ve grafiği şunları yapar:

| Olay | Grafik ne yapar |
|---|---|
| Construct | Süreç çalışıyorsa girdileri etkinleştirir, sonra `Call Plugin Process ("status")` ile her öğeyi yanıttan doldurur. |
| On Value Changed (ForceSimulation) | `setForceSimulation {value}` |
| On Selection Changed (TrackingOrigin / StereoMode) | Kullanıcının seçimleri için `setTrackingOrigin` / `setStereoMode {value}` (grafiğin kendi yaptığı seçim yok sayılır). |
| On Clicked (TogglePreview) | `toggleVrPreview` |
| Failed (her çağrı) | hatayı gösteren bir toast. |
| On Plugin Process Event (`openxr.status`) | her öğeyi olayın durumundan doldurur: düğme Start ya da Stop VR Preview, primary ya da destructive olur. |
| On Plugin Process State Changed | süreç çalışmazken girdileri devre dışı bırakır, yeniden çalışınca yeniler. |

Durum metinlerini (`RuntimeName`, `ManifestPath`, `RuntimeKind`, `SessionState`) süreç kendisi güncel tutar: her
değişiklikte her açık örnekte onları yamar (`PluginProcessContext.patchPanel`, grafik çalışmaz) ve `openxr.status`
yayar. Varlık yolu orada panelin adresidir; bu yüzden tek bir sabitte, `OpenXrPanel.asset`'te durur.

Paneli değiştirmek için eklentiyi kendi klasöründen açın (geliştirilmekte olan bir kullanıcı ya da proje eklentisi) ve
`EPW_OpenXR.lmas`'ı Widget Blueprint tasarımcısında düzenleyin: Editor palet bölümü, Class Settings ▸ Editor Panel ve
editör kapsamlı grafik paleti oradadır; **Run as Editor Panel** onu yuvada yeniden yükler, kaydetmek açık bir paneli
yerinde yeniler. Sürecin yamadığı öğe adlarını (`OpenXrPanel.patchedElements`) koruyun;
`test/editor_panel_asset_test.dart` bunları, panel bloğunu ve grafiğin yalnızca sürecin yanıtladığı yöntemleri
çağırdığını denetler.

## Kendi sürecinde çalışır

Manifest `"isolation": "process"` der: Lumina Studio eklentiyi kendi çalıştırılabilir dosyasının ayrı bir sürecinde
başlatır ve onunla yerel bir bağlantı üzerinden konuşur; böylece bir OpenXR çalışma zamanındaki ya da yerel köprüdeki
bir çökme veya kilitlenme editörü düşüremez.

| Nerede | Orada ne çalışır |
|---|---|
| Eklenti süreci (`LuminaPluginOpenxrProcess`, modülün `process_class`'ı) | Doğrudan `PluginProcessContext` ile kaydedilen `OpenXrController` (eklentinin durumu ve eylemleri, saf Dart): OpenXR yükleyici köprüsü (`dart:ffi`), `OpenXrBindings`, oturum, tüm menü ve durum çubuğu komutları, `get_status` MCP aracı, OpenXR panelinin çağırdığı yöntemler (`status`, `setForceSimulation`, `setTrackingOrigin`, `setStereoMode`, `toggleVrPreview`; her biri durum JSON'unu döner), `openxr.status` olayı ve durum metni yamaları, Output Log satırları. `LuminaPluginCrashReporter` ile bildirilen yakalanmış yerel hatalar eklentinin adıyla editör günlüğüne gider (eklenti süreci çalışma zamanı iletir). |
| Editör | OpenXR'a ait kod yok: modül yalnızca bir `process_class` adlandırır, `registration_class` yoktur; eklentinin editör içinde bir parçası olmaz (Plugin Manager onun için süreç içi geçersiz kılma sunmaz) ve editör köprüyü hiç açmaz. Editör menü öğelerini ve durum çubuğu düğmesini sürecin gönderdiklerinden çizer, OpenXR panelinin grafiğini kendi Blueprint VM'inde çalıştırır. Duruma ihtiyaç duyan editör kodu eklentinin süreç kanalını çağırır: `call('status')` `get_status` JSON'unu döner. |

Süreç durduğunda (bir çökme ya da art arda üç sağlık denetimine yanıt vermemesi) editör onu birkaç kez yeniden
başlatır, sonra eklentiyi durmuş olarak işaretler: menü öğeleri grileşir, OpenXR panelinin girdileri devre dışı
kalır, eklentinin **Restart** düğmesi görünür, Plugin Manager durumu, çıkış kodunu ve günlüğün sonunu gösterir ve bir eklenti çökme raporu
kaydedilir. Editör ve açık level çalışmaya devam eder. Yeniden başlatma yeni bir oturumla başlar (VR önizlemesi
kapalıdır).

Hata ayıklama: süreç parçası düz bir Dart programıdır; bir hata ayıklayıcıyla tek başına çalışır:
`dart run bin/openxr_process.dart --lumina-plugin-process lumina_plugin_openxr --lumina-plugin-port <port> ...`
(editörün testlerinin başlattığı budur; kütüphane yolunda yerel köprü yoksa benzetimli çalışma zamanını kullanır).
`registration_class` olmadığından eklenti editör sürecine zorlanamaz.

## Gözlük olmadan çalışmak

Eklentideki hiçbir şey donanım gerektirmez. Kayıtlı bir çalışma zamanı yokken (ya da **Force Simulated Runtime**
açıkken) `OpenXrBindings` her şeyi `SimulatedOpenXrBackend`'e yönlendirir: oturumlar başlar ve `focused` durumuna
gelir, baş ve kontrolcülerin makul pozları olur, girdiler ve titreşimler testlerden ya da araçlardan betiklenebilir.
`lumina_plugin_metaxr` bunun üzerine benzetimli el hareketlerini süren bir editör paneli ekler.

### Süreç bölümü

`LuminaPluginOpenxrProcess` ve içe aktardığı kütüphaneler (`OpenXrController`, `OpenXrPanel`, `OpenXrBindings`,
oturum ve OpenXR türleri) yalnızca `lumina_plugin_process`'i (eklenti süreci API'si; simgeler `PluginIconSpec`
verisidir), `ffi` ve `logging`'i (yükleyici köprüsü) ve `vector_math`'i kullanır: Flutter, `flutter_filament` ya da
`lumina_editor_api` yok. Köprünün `dart:ffi` çağrıları Flutter gerektirmez. `OpenXrFilamentBridge` (Filament stereo
eşlemesi, `flutter_filament`) ve motor bileşenleri
(`package:lumina`) süreç bölümünün dışındadır. `test/architecture/process_part_reach_test.dart` bunu korur. Paketin
kendisi yine Flutter'a bağlıdır; bu yüzden onu içe aktaran bir paket (yalnızca `xr_types.dart` olsa bile) onun
üzerinden Flutter'a bağlı olur.

## Mimari

```
lib/
  lumina_plugin_openxr.dart          genel kütüphane (aşağıdakilerin hepsini dışa aktarır)
  xr_types.dart                      yerel köprü olmadan düz XR türleri (LuminaXRHand, aksiyon durumu)
  src/process/    LuminaPluginOpenxrProcess (process_class), OpenXrController (durum ve eylemler, saf Dart),
                  OpenXrPanel (panel varlığının adresi, öğe adları, durum metinleri)
  src/ffi/        OpenXrBindings (yerel köprü + benzetim anahtarı), OpenXR türleri/yapıları, SimulatedOpenXrBackend
  src/session/    OpenXrSession, OpenXrReferenceSpace, OpenXrSpaceConverter
  src/input/      aksiyon kümesi, düğme/eksen/vector2 durumu, titreşim, etkileşim profili yolları
  src/components/ LuminaXROriginActor, LuminaXRHMDComponent, LuminaXRControllerComponent, LuminaXRHand
  src/render/     OpenXrStereoView, OpenXrFilamentBridge, OpenXrSwapchainDescriptor
bin/openxr_process.dart   süreç parçası düz bir Dart programı olarak
content/Editor/EPW_OpenXR.lmas   OpenXR paneli (editör paneli Widget Blueprint'i)
tool/pack_plugin.dart   eklentiyi Marketplace için paketler (content/ ile)
hook/build.dart   köprüyü derleyen Native Assets kancası
src/              openxr_bridge_c.h / .cpp (C API, FFI_PLUGIN_EXPORT)
```

- **Dart ↔ yerel.** Köprü beş C fonksiyonu dışa aktarır: `openxr_bridge_is_runtime_available`,
  `openxr_bridge_get_active_runtime_path`, `openxr_bridge_get_active_runtime_name`, `openxr_bridge_initialize`
  (başarıda 0) ve `openxr_bridge_shutdown`. `OpenXrBindings` bunları `dart:ffi` ile bulur, sonuçları `XrResult` ve
  Dart dizgilerine çevirir. Her çağrı korumalıdır; bir hata `package:logging` (logger `OpenXrBindings`) ile
  kaydedilir ve benzetime düşülür.
- **İş parçacıkları.** Tüm çağrılar eşzamanlıdır ve dünyanın sahibi olan Dart isolate'inden yapılır (Lumina
  Studio'da eklenti sürecinin isolate'i, hiçbir zaman editörünki değil). Köprü durumunu süreç genelindeki statik değişkenlerde tutar; tek bir isolate'ten çağırın.
- **Kare döngüsü.** Döngü oyunun (ya da aracın) elindedir: `session.pollEvents()`, pozları okuyun (bugün
  benzetimden), bileşenlere verin, göz görünümlerini kurun ve çiziciye verin. Instance/oturum oluşturma geldiğinde
  poz ve kare zamanlamasını köprü üstlenecek.
- **Stereo yolu.** OpenXR her göz için bir poz ve dört FOV yarı açısı verir; `OpenXrStereoView` bunları eksen dışı
  projeksiyona ve görünüm matrisine çevirir; `OpenXrFilamentBridge` Filament'i iki gözlü instanced ya da multiview
  çizim için yapılandırır (`OpenXrSwapchainDescriptor.arraySize` ile uyumlu, 2 katmanlı doku dizisine tek geçiş) ya da
  `separateViews` ile göz başına sıradan bir geçiş yapılır.

## Kare döngüsü

`xrWaitFrame` bloklar, bu yüzden hiçbir zaman bir Dart isolate'inde çalışmaz:

1. **Zamanlayıcı** (köprüdeki yerel bir iş parçacığı) her kareyi bekler, gözleri oturumun referans uzayında öngörülen
   gösterim zamanı için konumlar ve `(predictedDisplayTime, shouldRender, frame)` bilgisini bir
   `NativeCallable.listener` üzerinden UI isolate'ine gönderir (`OpenXrNativePacer`). Çalışma zamanının render
   istemediği bir kareyi zamanlayıcı kendisi boş olarak başlatıp bitirir.
2. **UI isolate'i** (`OpenXrFrameLoop`) görünümleri rig'e verir (`LuminaXRWorldDriver` bu karenin baş pozunu origin'in
   HMD bileşenine koyar), dünyayı çalışma zamanının deltasıyla tick'ler ve render eder.
3. **Renderer** (`OpenXrFilamentRenderer`) Filament'i çalışma zamanının kendi Vulkan cihazında çalıştırır
   (`XR_KHR_vulkan_enable2`; cihaz flutter_filament'in cihaz bilgisiyle, çalışma zamanı için bir, Filament için bir
   kuyrukla oluşturulur) ve iki gözü tek multiview geçişte 2 katmanlı bir sRGB swapchain görüntüsüne çizer.
   Filament'in sürücü iş parçacığı OpenXR karesini görüntüyü aldığında başlatır ve bıraktığında bir projeksiyon
   katmanıyla bitirir; böylece `xrEndFrame`, flush gerekmeden karenin GPU gönderiminden sonra gelir.

```dart
final session = OpenXrSession(backend: OpenXrBindings.instance.native)
  ..vulkanDeviceInfo = openXrFilamentDeviceInfo();
OpenXrFrameLoop? loop;
session.onSessionBegan = () {
  final renderer = OpenXrFilamentRenderer.create(OpenXrBindings.instance.native,
      spaceType: session.referenceSpaceType)!;
  // sahneyi renderer.scene içinde kurun (renderer.engine)
  loop = OpenXrFrameLoop(pacer: OpenXrNativePacer(OpenXrBindings.instance.native), renderer: renderer)..start();
};
session.onSessionEnding = () => loop?.stop();
session.beginSession();
// session.pollEvents()'i bir zamanlayıcıyla sorgulayın
```

Benzetimli başlığın kendi zamanlayıcısı vardır (`OpenXrSimulatedPacer`) ve `OpenXrFilamentRenderer.onSwapChain` aynı
şekilde herhangi bir swapchain'e render eder (masaüstü smoke, flutter_filament'in `ExternalVulkanOffscreen`'ini
kullanır). `example/` bir başlık için ayağa kaldırma uygulamasıdır: dönen küpler, her 5 sn'de loglanan kare
istatistikleri (`--dart-define=XR_REFRESH_RATE=90` başka bir hız ister). Quest 3S'te kare başına yaklaşık 0,25 ms Dart
CPU ve 0,7 ms GPU ile 72 Hz'de çalışır.

## Diğer eklentiler için genişletme noktaları

openxr eklentisi hiçbir üretici uzantısını bilmez; başka bir eklenti (MetaXR passthrough) oturuma ve karelere ekler:

- Oturum başlamadan önce `OpenXrExtensionRequests.add('XR_FB_passthrough')`: çalışma zamanı sunuyorsa instance onu ister.
- `OpenXrFrameLoop.layerContributors` içindeki `OpenXrLayerContributor`: her karede projeksiyon katmanının öncesi /
  sonrası için katmanlar (`OpenXrCompositionLayer`: bir ad ve `XrCompositionLayer*` yapısının adresi), projeksiyon
  katmanının bayrakları (`OpenXrCompositionLayerFlags`), bir ortam karışım modu ve oyunun alfa 0 ile temizleyip
  temizlemeyeceği sorulur (`OpenXrFilamentRenderer` bir `OpenXrTransparencyAware`'dir). Köprü bunları her `xrEndFrame`
  ile gönderir (`openxr_bridge_set_frame_layers`, `openxr_bridge_set_environment_blend_mode`).
- Diğer eklentinin yerel kodu için `OpenXrNativeBackend.instanceProcAddr` / `instanceHandle` / `sessionHandle`;
  `OpenXrSession.eventListeners` her olayı alır, uzantı olaylarını `OpenXrOtherEvent(structureType, payload)` olarak.

## Koordinat sistemleri ve birimler

| | Birim | Eksenler |
|---|---|---|
| OpenXR | metre | sağ el kuralı, X sağ, Y yukarı, −Z ileri |
| Lumina (saklanan dönüşümler) | santimetre (bir dünya birimi = 1 cm) | Z yukarı |

Lumina'nın çalışma zamanı OpenXR'in eksenlerine (Y yukarı, −Z ileri, +X sağ) santimetre olarak sahiptir; bu yüzden
`OpenXrSpaceConverter.openXrToRuntimePosition` yalnızca 100 ile ölçekler ve `openXrToRuntimeRotation` dönüşü korur;
HMD ve kontrolcü bileşenleri bunları kullanır. Saklanan (yazım) dönüşümleri Z yukarıdır ve `LuminaAxes` üzerinden
geçer: `openXrToLuminaPosition` yazım konumunu `(x, −z, y) × 100` olarak verir (ileri +Y, yukarı +Z),
`luminaToOpenXrPosition` geri dönüşü, `openXrToLuminaRotation` ise yönelimler için aynı taban değişimini. Benzetim ve
stereo matematiği, çalışma zamanının bildirdiği gibi OpenXR metresinde kalır.

## Testler

Birim testleri benzetimli arka uçta çalışır; başlık ya da GPU gerektirmez:

```bash
flutter test test/architecture/process_part_reach_test.dart
flutter test test/openxr_loader_and_types_test.dart
flutter test test/openxr_session_and_spaces_test.dart
flutter test test/openxr_stereo_render_test.dart
flutter test test/xr_components_test.dart
flutter test test/openxr_plugin_process_test.dart
flutter test test/editor_panel_asset_test.dart
flutter test test/architecture/no_legacy_ui_test.dart
flutter test test/pack_plugin_test.dart
flutter test test/xr_types_library_test.dart
flutter test test/openxr_session_state_machine_test.dart
flutter test test/openxr_stereo_view_test.dart
flutter test test/openxr_space_converter_test.dart
flutter test test/runtime_import_graph_test.dart
flutter test test/hook_android_test.dart
flutter test test/openxr_frame_loop_test.dart
flutter test test/openxr_eye_camera_test.dart
flutter test test/xr_world_driver_test.dart
flutter test test/openxr_multiview_choice_test.dart
flutter test test/openxr_bindings_test.dart
flutter test test/openxr_input_hysteresis_test.dart
flutter test test/openxr_input_system_test.dart
flutter test test/openxr_haptics_test.dart
flutter test test/openxr_blueprint_nodes_test.dart
dart run tool/smoke_report.dart test/smoke/openxr_frame_loop_smoke_test.dart --no-dashboard
dart run tool/smoke_report.dart test/smoke/openxr_input_smoke_test.dart --no-dashboard
flutter analyze
```

Sonuç kodlarını ve yapı düzenlerini, benzetime düşmeyi, oturum durumlarını ve izleme orijinlerini, koordinat
dönüşümünü, girdi durumlarını, projeksiyon matrisini (sonlu değerler), Filament stereo eşlemesini, origin aktörünün
bileşenlerini kapsarlar.
`openxr_plugin_process_test.dart` süreç parçasını `runPluginProcessMain` ile `LoopbackHost`'a (gerçek bir loopback
soketi üzerinden editör tarafı) karşı çalıştırır: katkılar, durum düğmesinin canlı durumu ve menüsü, menü onay işareti,
panelin yöntemleri (kötü bir değer için `bad_arguments`), `openxr.status` olayı ve durum metni yamaları, editör
panelini açan komutlar, MCP aracı, süreci bitirmeden yanıtlanan hatalar, editör günlüğündeki çökme raporları ve temiz
kapanış. `editor_panel_asset_test.dart` `EPW_OpenXR.lmas`'ı okur (panel bloğu, sürecin yamadığı öğeler, seçenekler ve
etiketler, grafiğin sürecin yöntemlerine karşı denetimi); `no_legacy_ui_test.dart` `lib/`'i editör içi bir parçadan
arı tutar; `pack_plugin_test.dart` bir kopyayı paketler ve paneli zip'te bulur. Lumina Studio'nun
`test/ui/editor_panels/openxr_editor_panel_test.dart` testi bu checkout'u gerçek süreciyle bir kullanıcı eklentisi
olarak çalıştırır (`../openxr` değilse `LUMINA_OPENXR_DIR`'i ayarlayın).

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

- Yalnızca multiview düzeni render ediliyor; göz başına geri düşüş (iki swapchain, iki view) `OpenXrStereoLayout`
  tarafından seçiliyor ama henüz çizilmiyor. Quest 3S multiview destekliyor.
- İstenen bir yenileme hızı (`requestDisplayRefreshRate(90)`) kabul edildi, ancak kimse takmıyorken Quest 72 Hz'de kaldı.
- OpenXR panelinde seçilen stereo modu henüz eklentinin `OpenXrFilamentBridge`'ine aktarılmıyor.
- Yerel yol geliştirilirken bir PC çalışma zamanı yoktu; masaüstü köprüsü derleniyor ve bir çalışma zamanını aynı
  şekilde buluyor, ancak yalnızca Quest üzerinde çalıştı.

Sıradakiler: el izleme.

## Katkı

Issue ve pull request'ler memnuniyetle karşılanır. Analizörü temiz tutun (`flutter analyze`), yeni davranış için bir
birim testi ekleyin (testler benzetimli arka ucu kullanır; motorun sahtesi yazılmaz) ve iki README'yi (İngilizce ve
Türkçe) birlikte güncel tutun. Eklentinin arayüzü editör paneli Widget Blueprint'idir: onu Dart'ta değil
tasarımcıda değiştirin.

## Lisans

MIT — bkz. [LICENSE](LICENSE).

Bu depo üçüncü taraf kaynak kodu ya da ikili dosya içermez. Çalışma anında makinede zaten kurulu olan OpenXR
yükleyicisini ve çalışma zamanını açar (Khronos OpenXR yükleyicisi Apache-2.0'dır; çalışma zamanlarının kendi
lisansları vardır). OpenXR™, The Khronos Group Inc.'in ticari markasıdır.
