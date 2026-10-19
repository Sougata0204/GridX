import sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

def parse_vcd(vcd_path):
    var_map = {} # id -> name
    type_map = {} # id -> size
    data = {} # id -> list of (time_ps, value)
    
    with open(vcd_path, 'r', encoding='utf-8', errors='ignore') as f:
        in_header = True
        current_time = 0
        
        for line in f:
            line = line.strip()
            if not line:
                continue
            if in_header:
                if line.startswith('$var'):
                    parts = line.split()
                    # $var wire 1 # hostStart $end
                    # $var wire 32 + perfHbmReads [31:0] $end
                    if len(parts) >= 5:
                        var_id = parts[3]
                        var_name = parts[4]
                        var_map[var_id] = var_name
                        data[var_id] = []
                elif line.startswith('$enddefinitions'):
                    in_header = False
            else:
                if line.startswith('#'):
                    current_time = int(line[1:])
                elif line.startswith('$'):
                    continue
                else:
                    # value change: '0!', '1!', 'b101 ('
                    if line.startswith('b') or line.startswith('B'):
                        parts = line.split()
                        val_str = parts[0][1:]
                        var_id = parts[1]
                        try:
                            val = int(val_str, 2)
                        except ValueError:
                            val = 0
                        if var_id in data:
                            data[var_id].append((current_time, val))
                    else:
                        val_char = line[0]
                        var_id = line[1:]
                        val = 1 if val_char == '1' else 0
                        if var_id in data:
                            data[var_id].append((current_time, val))
                            
    return var_map, data

def plot_waveforms(vcd_path, output_png):
    var_map, data = parse_vcd(vcd_path)
    # Reverse lookup name -> id
    name_to_id = {v: k for k, v in var_map.items()}
    
    # Selected key signals to plot
    target_signals = [
        ('rst_n', 'Active-Low Reset (rst_n)', 'binary', '#2ca02c'),
        ('hostStart', 'Host Kernel Start (hostStart)', 'binary', '#d62728'),
        ('kernelStateO', 'Kernel FSM State (0:IDLE, 1:CFG, 2:LAUNCH, 3:RUN, 4:DRAIN, 5:DONE)', 'multi', '#9467bd'),
        ('dmWrValid', 'Core LSU Stores Active [7:0]', 'multi', '#ff7f0e'),
        ('meshFlitInValid', '3D NoC In-Flits Active [7:0]', 'multi', '#1f77b4'),
        ('meshFlitOutValid', '3D NoC Out-Flits / Z-Link Active [7:0]', 'multi', '#17becf'),
        ('perfTotalFlits', 'Total NoC / TSV Flit Counter', 'multi', '#e377c2'),
        ('perfHbmWrites', 'HBM3 Memory Writes Committed', 'multi', '#bcbd22'),
        ('kernelDone', 'Hardware Kernel Complete (kernelDone)', 'binary', '#2ca02c')
    ]
    
    active_plots = []
    for sig_name, display_name, sig_type, color in target_signals:
        if sig_name in name_to_id and len(data[name_to_id[sig_name]]) > 0:
            active_plots.append((sig_name, display_name, sig_type, color, data[name_to_id[sig_name]]))
            
    if not active_plots:
        print("No matching signals found to plot.")
        return
        
    fig, axes = plt.subplots(len(active_plots), 1, figsize=(14, 2.2 * len(active_plots)), sharex=True)
    if len(active_plots) == 1:
        axes = [axes]
        
    fig.patch.set_facecolor('#ffffff')
    
    # Determine max time in ns
    max_time_ns = max(pts[-1][0] for _, _, _, _, pts in active_plots) / 1000.0
    
    for i, (sig_name, display_name, sig_type, color, pts) in enumerate(active_plots):
        ax = axes[i]
        ax.set_facecolor('#fafafa')
        ax.grid(True, linestyle='--', alpha=0.5, color='#cccccc')
        
        times_ns = [t / 1000.0 for t, _ in pts]
        vals = [v for _, v in pts]
        
        # Extend to max_time_ns if needed
        if times_ns[-1] < max_time_ns:
            times_ns.append(max_time_ns)
            vals.append(vals[-1])
            
        if sig_type == 'binary':
            ax.step(times_ns, vals, where='post', color=color, linewidth=2.0)
            ax.fill_between(times_ns, vals, step='post', alpha=0.2, color=color)
            ax.set_ylim(-0.15, 1.25)
            ax.set_yticks([0, 1])
            ax.set_yticklabels(['0', '1'], fontsize=9, fontweight='bold')
        else:
            ax.step(times_ns, vals, where='post', color=color, linewidth=2.0)
            max_v = max(vals) if vals else 1
            ax.set_ylim(-0.05 * max_v, 1.15 * max_v if max_v > 0 else 1.0)
            
        ax.set_ylabel(sig_name, fontsize=10, fontweight='bold', color='#111111')
        ax.set_title(display_name, fontsize=10.5, loc='left', pad=4, fontweight='semibold', color='#222222')
        
    axes[-1].set_xlabel('Simulation Time (ns)', fontsize=11, fontweight='bold')
    plt.suptitle('GridX3 3D MemoryMesh SoC  Cycle-Accurate Time-Domain Simulation Waveform\n(Extracted directly from Vivado Simulator VCD Dump)', fontsize=14, fontweight='bold', y=0.995)
    plt.tight_layout(rect=[0, 0, 1, 0.97])
    plt.savefig(output_png, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Generated plot: {output_png} (Max time: {max_time_ns:.1f} ns)")

if __name__ == '__main__':
    vcd = sys.argv[1] if len(sys.argv) > 1 else 'gridx_run.vcd'
    out = sys.argv[2] if len(sys.argv) > 2 else 'gridx3_time_domain_plot.png'
    plot_waveforms(vcd, out)
