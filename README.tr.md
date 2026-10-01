# Lumina Studio için OpenXR Eklentisi (`lumina_plugin_openxr`)

Lumina oyun motoru ve Lumina Studio için platformlar arası Khronos OpenXR 1.0/1.1 entegrasyonu.

## Özellikler

- **Platformlar Arası OpenXR**: Meta Quest Link, SteamVR, Windows Mixed Reality, Monado ve Varjo ile tam uyumlu.
- **Native Assets Entegrasyonu**: `hook/build.dart` aracılığıyla derlenen yerel C köprüsü, Windows'ta etkin runtime registry kayıtlarını ve Linux'ta sistem loader kütüphanelerini dinamik olarak keşfeder.
- **Simüle XR Runtime**: Fiziksel bir VR başlığına ihtiyaç duymadan test ve geliştirme yapmayı sağlayan yerleşik 6-DOF simülatör modu.
- **Stereoskopik Render**: OpenXR asimetrik görüş alanı (FOV) ve göz bebekleri arası mesafe (IPD) verilerini doğrudan Google Filament'in stereoskopik render ardışık düzenine bağlar (`StereoscopicType.instanced` ve `StereoscopicType.multiview`).
- **Motor Bileşenleri**:
  - `LuminaXROriginActor`: Zemin seviyesi (Floor), Göz seviyesi (Eye-level) ve Oda ölçeği (Stage) uzaylarını destekleyen XR kök aktörü.
  - `LuminaXRHMDComponent`: Göz bakış noktalarını yönlendiren gerçek zamanlı baş takip bileşeni.
  - `LuminaXRControllerComponent`: Sol ve Sağ kontrolcüler için tutuş/hedef (grip/aim) takibi, analog tetik/thumbstick eksenleri, butonlar ve haptik titreşim geri bildirimi.
- **Editör Entegrasyonu**: Durum çubuğunda canlı OpenXR rozeti, VR Önizleme düğmesi, XR Ayarları paneli ve yapay zeka aracı `openxr.get_status`.

## Kurulum

Projenizin `pubspec.yaml` dosyasına ekleyin veya **Plugins → Plugin Manager** üzerinden etkinleştirin:

```yaml
dependencies:
  lumina_plugin_openxr:
    path: ../openxr
```

## Mimari

- `lib/src/ffi/`: OpenXR FFI struct yapıları, yerel loader araması ve simülatör arka ucu.
- `lib/src/session/`: Oturum durum makinesi ve koordinat dönüşümleri (OpenXR metre Y-yukarı -> Lumina cm Z-yukarı).
- `lib/src/input/`: Aksiyon kümeleri, eksen durumları ve etkileşim profili bağlamaları.
- `lib/src/components/`: XR Origin aktörü, HMD bileşeni ve kontrolcü bileşenleri.
- `lib/src/render/`: Asimetrik projeksiyon matematiği ve Filament stereoskopik köprüsü.
- `lib/src/ui/`: shadcn_flutter durum rozeti ve XR ayarları formu.

## Lisans

MIT Lisansı. Bkz: [LICENSE](file:///d:/lumina/openxr/LICENSE).
