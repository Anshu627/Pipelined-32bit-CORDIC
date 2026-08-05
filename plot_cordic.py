import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

os.makedirs('plots', exist_ok=True)

try:
    df = pd.read_csv('cordic_results.csv')
except FileNotFoundError:
    print("Error: cordic_results.csv not found.")
    exit()

# Helper function to calculate hardware accuracy
def calculate_accuracy(hw, ideal, name):
    abs_err = np.abs(hw - ideal)
    max_err = np.max(abs_err)
    
    # Ignore values where ideal is extremely close to zero to prevent divide-by-zero
    mask = np.abs(ideal) > 1e-4
    if np.any(mask):
        mape = np.mean(np.abs((hw[mask] - ideal[mask]) / ideal[mask])) * 100
        accuracy = 100.0 - mape
    else:
        accuracy = 100.0
        
    return f"{name:<10} | {accuracy:>9.4f}% | {max_err:>11.2e}"

# Helper function to generate plots
def create_plot(filename, title, input_val, hw_y1, ideal_y1, label1, hw_y2=None, ideal_y2=None, label2=None, xlabel="Input"):
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), gridspec_kw={'height_ratios': [2, 1]})
    
    ax1.plot(input_val, hw_y1, 'bo', label=f'HW {label1}', markersize=4, alpha=0.7)
    ax1.plot(input_val, ideal_y1, 'k-', label=f'Ideal {label1}', linewidth=1.5)
    err1 = hw_y1 - ideal_y1
    ax2.plot(input_val, err1, 'b-', label=f'{label1} Error')
    
    if hw_y2 is not None:
        ax1.plot(input_val, hw_y2, 'ro', label=f'HW {label2}', markersize=4, alpha=0.7)
        ax1.plot(input_val, ideal_y2, 'g-', label=f'Ideal {label2}', linewidth=1.5)
        err2 = hw_y2 - ideal_y2
        ax2.plot(input_val, err2, 'r-', label=f'{label2} Error')
        
    ax1.set_title(title)
    ax1.grid(True, linestyle='--', alpha=0.6)
    ax1.legend()
    
    ax2.set_title('Quantization Error (HW - Ideal)')
    ax2.set_xlabel(xlabel)
    ax2.grid(True, linestyle='--', alpha=0.6)
    ax2.ticklabel_format(axis='y', style='sci', scilimits=(0,0))
    ax2.legend()
    
    plt.tight_layout()
    filepath = os.path.join('plots', filename)
    plt.savefig(filepath, dpi=300, bbox_inches='tight')
    plt.close() 

# --- Generate Plots and Print Accuracy Table ---
print("\n" + "="*40)
print(" 32-BIT CORDIC HARDWARE ACCURACY REPORT")
print("="*40)
print(f"{'FUNCTION':<10} | {'ACCURACY %':>10} | {'MAX ERROR':>11}")
print("-" * 40)

# 1. Sin / Cos
d = df[df['test_id'] == 1]
ideal_cos = np.cos(np.radians(d['input_val']))
ideal_sin = np.sin(np.radians(d['input_val']))
create_plot('1_sin_cos.png', 'Sin(x) and Cos(x)', d['input_val'], d['out_x'], ideal_cos, 'Cos', d['out_y'], ideal_sin, 'Sin', "Input Angle (Degrees)")
print(calculate_accuracy(d['out_x'], ideal_cos, "Cosine"))
print(calculate_accuracy(d['out_y'], ideal_sin, "Sine"))

# 2. Arctan
d = df[df['test_id'] == 2]
hw_arctan = d['out_z'] * 180.0 / np.pi
ideal_arctan = np.degrees(np.arctan(d['input_val']))
create_plot('2_arctan.png', 'Arctan(x)', d['input_val'], hw_arctan, ideal_arctan, 'Arctan', xlabel="Input Ratio (Y/X)")
print(calculate_accuracy(hw_arctan, ideal_arctan, "Arctan"))

# 3. Sinh / Cosh
d = df[df['test_id'] == 3]
ideal_cosh = np.cosh(d['input_val'])
ideal_sinh = np.sinh(d['input_val'])
create_plot('3_sinh_cosh.png', 'Sinh(x) and Cosh(x)', d['input_val'], d['out_x'], ideal_cosh, 'Cosh', d['out_y'], ideal_sinh, 'Sinh', "Input Radians")
print(calculate_accuracy(d['out_x'], ideal_cosh, "Cosh"))
print(calculate_accuracy(d['out_y'], ideal_sinh, "Sinh"))

# 4. Exponential (e^x)
d = df[df['test_id'] == 4]
ideal_exp = np.exp(d['input_val'])
create_plot('4_exp.png', 'Exponential (e^x)', d['input_val'], d['out_x'], ideal_exp, 'e^x', xlabel="Input Value (x)")
print(calculate_accuracy(d['out_x'], ideal_exp, "e^x"))

# 5. Arctanh
d = df[df['test_id'] == 5]
ideal_arctanh = np.arctanh(d['input_val'])
create_plot('5_arctanh.png', 'Arctanh(x)', d['input_val'], d['out_z'], ideal_arctanh, 'Arctanh', xlabel="Input Value (x)")
print(calculate_accuracy(d['out_z'], ideal_arctanh, "Arctanh"))

# 6. Natural Log (ln)
d = df[df['test_id'] == 6]
hw_ln = d['out_z'] * 2.0
ideal_ln = np.log(d['input_val'])
create_plot('6_natural_log.png', 'Natural Logarithm ln(x)', d['input_val'], hw_ln, ideal_ln, 'ln(x)', xlabel="Input Value (x)")
print(calculate_accuracy(hw_ln, ideal_ln, "ln(x)"))

# 7. Square Root
d = df[df['test_id'] == 7]
hw_sqrt = d['out_x'] * 1.207497067
ideal_sqrt = np.sqrt(d['input_val'])
create_plot('7_sqrt.png', 'Square Root', d['input_val'], hw_sqrt, ideal_sqrt, 'Sqrt(x)', xlabel="Input Value (x)")
print(calculate_accuracy(hw_sqrt, ideal_sqrt, "Sqrt(x)"))

print("="*40)
print("Plots saved successfully in /plots/ directory.\n")