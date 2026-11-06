"""Export Linux and tray icons. Run dart run flutter_launcher_icons for macOS/Windows."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'assets/icons'
app = Image.open(ICONS / 'app-icon-source.png').convert('RGBA')


def export(image, path, size):
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)


export(app, ICONS / 'app_icon.png', 512)
export(app, ROOT / 'linux/runner/resources/app_icon.png', 512)

# The tray uses a separate background-free face, with padding for taskbar scaling.
tray = Image.open(ROOT / 'tools/icons/tray-icon-source.png').convert('RGBA')
bounds = tray.getchannel('A').point(lambda value: 255 if value > 128 else 0).getbbox()
face = tray.crop(bounds)
face.thumbnail((896, 896), Image.Resampling.LANCZOS)
canvas = Image.new('RGBA', (1024, 1024))
canvas.alpha_composite(face, ((1024 - face.width) // 2, (1024 - face.height) // 2))
for size in (16, 20, 24, 32, 48, 64, 256):
    export(canvas, ICONS / f'tray_icon_{size}.png', size)
canvas.save(ICONS / 'tray_icon.ico', sizes=[(s, s) for s in (16, 20, 24, 32, 48, 64, 256)])
print('Exported Linux and tray icon assets.')
