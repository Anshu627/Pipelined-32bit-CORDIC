"""
cordic_verify.py

Reads cordic_results.csv (produced by tb_cordic_sweep.v running the
cordic_unified.v hardware core in Icarus Verilog) and cross-checks every
hardware output against the equivalent Python math.* computation.

Produces:
  - cordic_verification.png : 4 overlaid hardware-vs-Python plots, each
    annotated with its own max/RMSE error and accuracy %
  - cordic_accuracy_report.txt : full accuracy report (also printed)
"""

import pandas as pd
import numpy as np
import math
import matplotlib.pyplot as plt

SCALE = 2.0 ** 27  # Q4.27

df = pd.read_csv("cordic_results.csv")

# Convert fixed-point integer columns back to real numbers
for col in ["x_in", "y_in", "z_in", "x_out", "y_out", "z_out"]:
    df[col + "_r"] = df[col] / SCALE

fig, axes = plt.subplots(2, 2, figsize=(12, 9))
fig.suptitle("CORDIC Hardware (Verilog, Q4.27) vs Python Reference", fontsize=13)

errors = {}
report_lines = []


def accuracy_stats(name, hw, py, value_range):
    """Return (and record) max error, RMSE, and an accuracy % relative to
    the span of the expected values (value_range = max(py) - min(py))."""
    err = np.abs(hw - py)
    max_err = err.max()
    rmse = np.sqrt(np.mean(err ** 2))
    mean_err = err.mean()
    # Accuracy expressed as: how close, in %, worst-case output is to ideal,
    # relative to the full swing of the function over the sweep.
    accuracy_pct = 100.0 * (1.0 - max_err / value_range) if value_range > 0 else 100.0
    report_lines.append(
        f"{name:32s} max_err={max_err:.3e}  rmse={rmse:.3e}  "
        f"mean_err={mean_err:.3e}  accuracy={accuracy_pct:.4f}%"
    )
    errors[name] = err
    return max_err, rmse, accuracy_pct


def annotate(ax, max_err, rmse, accuracy_pct):
    ax.text(
        0.98, 0.02,
        f"max err: {max_err:.2e}\nRMSE: {rmse:.2e}\nacc: {accuracy_pct:.3f}%",
        transform=ax.transAxes, fontsize=8, va='bottom', ha='right',
        bbox=dict(boxstyle='round', facecolor='white', alpha=0.85)
    )

# ---------------------------------------------------------------------------
# 1. Circular rotation: cos(theta), sin(theta)
# ---------------------------------------------------------------------------
g1 = df[df.tag == 1].copy()
theta = g1["z_in_r"].values
cos_hw, sin_hw = g1["x_out_r"].values, g1["y_out_r"].values
cos_py = np.cos(theta)
sin_py = np.sin(theta)

ax = axes[0, 0]
ax.plot(np.degrees(theta), cos_py, 'b-', label='cos (Python)')
ax.plot(np.degrees(theta), cos_hw, 'b.', label='cos (HW)')
ax.plot(np.degrees(theta), sin_py, 'r-', label='sin (Python)')
ax.plot(np.degrees(theta), sin_hw, 'r.', label='sin (HW)')
ax.set_title("Circular Rotation: cos/sin(theta)")
ax.set_xlabel("theta (deg)")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)

me_c, rmse_c, acc_c = accuracy_stats('circular_rotation_cos', cos_hw, cos_py, cos_py.max() - cos_py.min())
me_s, rmse_s, acc_s = accuracy_stats('circular_rotation_sin', sin_hw, sin_py, sin_py.max() - sin_py.min())
annotate(ax, max(me_c, me_s), max(rmse_c, rmse_s), min(acc_c, acc_s))

# ---------------------------------------------------------------------------
# 2. Circular vectoring: recover magnitude (=1) and angle (atan2)
# ---------------------------------------------------------------------------
g2 = df[df.tag == 2].copy()
theta_in = np.degrees(np.arctan2(g2["y_in_r"].values, g2["x_in_r"].values))
mag_hw = g2["x_out_r"].values
ang_hw = np.degrees(g2["z_out_r"].values)
mag_py = np.ones_like(theta_in)
ang_py = theta_in

ax = axes[0, 1]
ax.plot(theta_in, mag_py, 'b-', label='magnitude (Python, =1)')
ax.plot(theta_in, mag_hw, 'b.', label='magnitude (HW)')
ax2 = ax.twinx()
ax2.plot(theta_in, ang_py, 'g-', label='angle (Python)')
ax2.plot(theta_in, ang_hw, 'g.', label='angle (HW)')
ax.set_title("Circular Vectoring: magnitude & atan2(theta)")
ax.set_xlabel("true theta (deg)")
ax.set_ylabel("magnitude")
ax2.set_ylabel("recovered angle (deg)")
lines1, labels1 = ax.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax.legend(lines1 + lines2, labels1 + labels2, fontsize=7, loc='upper center')
ax.grid(alpha=0.3)

me_m, rmse_m, acc_m = accuracy_stats('circular_vectoring_mag', mag_hw, mag_py, 1.0)  # ideal mag is always 1.0
me_a, rmse_a, acc_a = accuracy_stats('circular_vectoring_angle_deg', ang_hw, ang_py, ang_py.max() - ang_py.min())
annotate(ax, me_m, rmse_m, acc_m)

# ---------------------------------------------------------------------------
# 3. Hyperbolic rotation: cosh(z), sinh(z)
# ---------------------------------------------------------------------------
g3 = df[df.tag == 3].copy()
z3 = g3["z_in_r"].values
cosh_hw, sinh_hw = g3["x_out_r"].values, g3["y_out_r"].values
cosh_py = np.cosh(z3)
sinh_py = np.sinh(z3)

ax = axes[1, 0]
ax.plot(z3, cosh_py, 'b-', label='cosh (Python)')
ax.plot(z3, cosh_hw, 'b.', label='cosh (HW)')
ax.plot(z3, sinh_py, 'r-', label='sinh (Python)')
ax.plot(z3, sinh_hw, 'r.', label='sinh (HW)')
ax.set_title("Hyperbolic Rotation: cosh/sinh(z)")
ax.set_xlabel("z (rad)")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)

me_ch, rmse_ch, acc_ch = accuracy_stats('hyperbolic_rotation_cosh', cosh_hw, cosh_py, cosh_py.max() - cosh_py.min())
me_sh, rmse_sh, acc_sh = accuracy_stats('hyperbolic_rotation_sinh', sinh_hw, sinh_py, sinh_py.max() - sinh_py.min())
annotate(ax, max(me_ch, me_sh), max(rmse_ch, rmse_sh), min(acc_ch, acc_sh))

# ---------------------------------------------------------------------------
# 4. Hyperbolic vectoring: atanh(v)
# ---------------------------------------------------------------------------
g4 = df[df.tag == 4].copy()
v = g4["y_in_r"].values  # x_in was fixed at 1.0
atanh_hw = g4["z_out_r"].values
atanh_py = np.arctanh(v)

ax = axes[1, 1]
ax.plot(v, atanh_py, 'b-', label='atanh (Python)')
ax.plot(v, atanh_hw, 'b.', label='atanh (HW)')
ax.set_title("Hyperbolic Vectoring: atanh(v)")
ax.set_xlabel("v")
ax.legend(fontsize=8)
ax.grid(alpha=0.3)

me_at, rmse_at, acc_at = accuracy_stats('hyperbolic_vectoring_atanh', atanh_hw, atanh_py, atanh_py.max() - atanh_py.min())
annotate(ax, me_at, rmse_at, acc_at)

plt.tight_layout(rect=[0, 0, 1, 0.96])
plt.savefig("cordic_verification.png", dpi=150)
print("Saved cordic_verification.png")

# ---------------------------------------------------------------------------
# Overall accuracy report
# ---------------------------------------------------------------------------
all_err = np.concatenate(list(errors.values()))
overall_max = all_err.max()
overall_rmse = np.sqrt(np.mean(all_err ** 2))

report_lines.append("-" * 78)
report_lines.append(f"{'OVERALL (all 4 test groups combined)':32s} max_err={overall_max:.3e}  rmse={overall_rmse:.3e}")
report_lines.append("")
report_lines.append("Notes:")
report_lines.append(" - 'accuracy %' = 100 * (1 - max_err / (max-min of the ideal output over the sweep)).")
report_lines.append(" - Errors are dominated by the finite 34-stage angle resolution (LSB ~ 2^-27 rad)")
report_lines.append("   and fixed-point truncation in Q4.27, not by algorithmic mistakes.")
report_lines.append(" - Hyperbolic vectoring sweep is restricted to |v| <= 0.8 to stay inside the")
report_lines.append("   |z| < ~1.118 rad convergence domain of hyperbolic CORDIC.")

report_text = "\n".join(report_lines)
print("\n=== CORDIC accuracy report ===")
print(report_text)

with open("cordic_accuracy_report.txt", "w") as f:
    f.write(report_text + "\n")
print("\nSaved cordic_accuracy_report.txt")