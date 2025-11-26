# Images Folder

This folder is for storing image assets used in the Smart Bus Tracking app.

## Usage

After adding images to this folder, you can use them in your Flutter code like this:

```dart
// Example: Display an image
Image.asset('assets/images/your_image.png')

// Example: Use as background
decoration: BoxDecoration(
  image: DecorationImage(
    image: AssetImage('assets/images/your_image.png'),
    fit: BoxFit.cover,
  ),
),
```

## Recommended Images

Consider adding the following images for your FYP:
- `bus_icon.png` - Custom bus icon for markers
- `logo.png` - App logo for splash screen or about page
- `commuter_icon.png` - Icon for commuter role
- `driver_icon.png` - Icon for driver role
- `route_background.png` - Background image for route selection

## Image Formats

Supported formats: PNG, JPG, JPEG, GIF, WebP, BMP

## Notes

- Keep image file sizes optimized for mobile (< 500KB recommended)
- Use descriptive filenames (lowercase with underscores)
- After adding new images, run `flutter pub get` (though it's not always required for assets)

