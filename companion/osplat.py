"""The platform layer: platform_win.py or platform_mac.py, both with the same functions."""

import sys

if sys.platform == "darwin":
    from platform_mac import *  # noqa: F401,F403
else:
    from platform_win import *  # noqa: F401,F403
