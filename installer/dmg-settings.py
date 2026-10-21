# Tampilan jendela DMG, dipakai dmgbuild (pip install dmgbuild):
#   dmgbuild -s dmg-settings.py -D app="<path Cognify Notch.app>" -D dir="<folder installer>" "Cognify Notch" out.dmg
# Latar 660 x 400 poin (ada versi @2x di dalam TIFF). Ikon app di kiri, Applications di kanan,
# panah di latar menunjuk dari yang kiri ke yang kanan.
import os

app = defines["app"]  # noqa: F821 (disediakan dmgbuild)
here = defines["dir"]  # noqa: F821

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(here, "VolumeIcon.icns")
background = os.path.join(here, "dmg-background.tiff")
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 200), (660, 400))
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (170, 218), "Applications": (490, 218)}
default_view = "icon-view"
