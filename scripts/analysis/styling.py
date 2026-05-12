import matplotlib.pyplot as plt

# ── Plot styling ──────────────────────────────────────────────────────────────
COLOR_A    = "#4C72B0"   # blue  — eval A
COLOR_B    = "#DD8452"   # orange — eval B
ALPHA_BAND = 0.15        # opacity of ±std shaded bands

plt.rcParams.update({
    "figure.dpi":        120,
    "axes.spines.top":   False,
    "axes.spines.right": False,
    "axes.grid":         True,
    "grid.alpha":        0.35,
    "axes.titlesize":    11,
    "axes.labelsize":    9,
    "xtick.labelsize":   8,
    "ytick.labelsize":   8,
})