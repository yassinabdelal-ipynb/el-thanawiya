"""Render the app's simple vector mark into Android and web icon sizes."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]

def icon(size):
    image = Image.new('RGB', (1024, 1024), '#29322c')
    draw = ImageDraw.Draw(image)
    # Geometric E and T, sized for the Android launcher mask.
    draw.rounded_rectangle((235, 275, 315, 750), radius=30, fill='#ecede6')
    for y in [275, 472, 672]:
        draw.rounded_rectangle((235, y, 470, y + 78), radius=28, fill='#ecede6')
    draw.rounded_rectangle((545, 275, 800, 353), radius=28, fill='#ecede6')
    draw.rounded_rectangle((633, 300, 713, 750), radius=28, fill='#ecede6')
    return image.resize((size, size), Image.Resampling.LANCZOS)

for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    icon(size).save(ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / ('mipmap-' + density) / 'ic_launcher.png')
for size in (192, 512):
    for name in ('Icon-', 'Icon-maskable-'):
        icon(size).save(ROOT / 'web' / 'icons' / f'{name}{size}.png')
icon(32).save(ROOT / 'web' / 'favicon.png')
assets = ROOT / 'design'; assets.mkdir(exist_ok=True)
icon(512).save(assets / 'app-icon.png')
res = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
styles = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="forma_background">#ECEDE6</color>
  <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
    <item name="android:windowLightStatusBar">true</item>
    <item name="android:statusBarColor">@android:color/transparent</item>
    <item name="android:navigationBarColor">@color/forma_background</item>
  </style>
  <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@color/forma_background</item>
    <item name="android:windowLightStatusBar">true</item>
    <item name="android:navigationBarColor">@color/forma_background</item>
  </style>
</resources>'''
for name in ('values', 'values-night'):
    content = styles
    if name == 'values-night':
        content = content.replace('#ECEDE6', '#232B26').replace('<item name="android:windowLightStatusBar">true</item>', '<item name="android:windowLightStatusBar">false</item>')
    (res / name / 'styles.xml').write_text(content)

for directory, color in [('drawable', '#29322c'), ('drawable-night', '#edf0e6')]:
    destination = res / directory; destination.mkdir(exist_ok=True)
    wordmark = Image.new('RGBA', (1024, 1024), (0,0,0,0))
    painter = ImageDraw.Draw(wordmark)
    font = ImageFont.truetype(str(ROOT / 'assets' / 'fonts' / 'Manrope.ttf'), 105)
    font.set_variation_by_axes([450])
    painter.text((512,512), 'El-Thanawiya', font=font, fill=color, anchor='mm')
    wordmark.save(destination / 'brand_wordmark.png')

native = res / 'values-v31'; native.mkdir(exist_ok=True)
(native / 'styles.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
    <item name="android:windowSplashScreenBackground">@color/forma_background</item>
    <item name="android:windowSplashScreenAnimatedIcon">@drawable/brand_wordmark</item>
    <item name="android:navigationBarColor">@color/forma_background</item>
  </style>
</resources>''')
night_native = res / 'values-night-v31'; night_native.mkdir(exist_ok=True)
(night_native / 'styles.xml').write_text((native / 'styles.xml').read_text())
for name in ('drawable', 'drawable-v21'):
    (res / name / 'launch_background.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
  <item android:drawable="@color/forma_background" />
  <item android:width="280dp" android:height="280dp" android:gravity="center">
    <bitmap android:gravity="fill" android:src="@drawable/brand_wordmark" />
  </item>
</layer-list>''')
print('El-Thanawiya icons, text wordmark, and day/night launch themes ready.')
