# Colored Bus Icons - Naming Scheme

All bus icons follow the naming pattern: `bus_icon_{color}.png`

## Icon Files (32x32 pixels)

Place these PNG files in the `assets/icons/` folder:

1. **bus_icon_green.png** ✅ (Already exists)
   - Color: Green (#00FF00 or similar)
   - Used for: "In Service" status
   - Size: 32x32 pixels (automatically resized)

2. **bus_icon_red.png** ✅ (Already exists)
   - Color: Red (#FF0000 or similar)
   - Used for: "Breakdown" status
   - If missing: Falls back to default red pin marker

3. **bus_icon_orange.png** ✅ (Already exists)
   - Color: Orange (#FFA500 or similar)
   - Used for: "Delayed" status
   - If missing: Falls back to default orange pin marker

4. **bus_icon_blue.png** ✅ (Already exists)
   - Color: Blue (#0080FF or similar)
   - Used for: "Full Capacity" status
   - If missing: Falls back to default blue pin marker

5. **bus_icon_yellow.png** (To be added)
   - Color: Yellow (#FFFF00 or similar)
   - Used for: "Signal Weak" (stale GPS >30s)
   - If missing: Falls back to default yellow pin marker

## How to Create Colored Icons

### Option 1: Using Image Editor (Photoshop, GIMP, etc.)
1. Open `bus_icon.png`
2. Use "Color Overlay" or "Hue/Saturation" adjustment
3. Change the color to red/orange/blue/yellow
4. Save as the appropriate filename
5. Ensure transparent background is preserved

### Option 2: Using Online Tools
- **Photopea** (Free Photoshop alternative): https://www.photopea.com/
- **Remove.bg** + Color editor tools
- **Canva** with color filters

### Option 3: Using Flutter (Programmatic)
If you want to tint images programmatically, you'd need to use `ColorFiltered` widget, but this doesn't work with `BitmapDescriptor`. Separate PNG files are the recommended approach.

## Icon Specifications

- **Format**: PNG with transparent background
- **Recommended Size**: 64x64, 128x128, or 256x256 pixels
- **Will be displayed as**: 32x32 pixels on map (resized automatically)
- **Color**: Solid color with transparency for best results

## Current Behavior

### With Colored Icons:
- ✅ **In Service**: Shows `bus_icon.png` (your custom icon)
- 🔴 **Breakdown**: Shows `bus_icon_red.png` (or default red pin if missing)
- 🟠 **Delayed**: Shows `bus_icon_orange.png` (or default orange pin if missing)
- 🔵 **Full Capacity**: Shows `bus_icon_blue.png` (or default blue pin if missing)
- 🟡 **Signal Weak**: Shows `bus_icon_yellow.png` (or default yellow pin if missing)

### Without Colored Icons (Current):
- All statuses show the same `bus_icon.png` (black bus)
- Status is indicated by the text in the info window

## Testing

After adding the colored icons:
1. Stop the app completely
2. Run: `flutter clean`
3. Run: `flutter pub get`
4. Rebuild and run the app
5. Change bus status in the Driver app
6. Watch the commuter map - icon should change color!

## Tips

- Keep the same bus silhouette/shape for all colors
- Use bold, saturated colors for better visibility on the map
- Test on both light and dark map themes
- Icons will be displayed small, so avoid fine details

