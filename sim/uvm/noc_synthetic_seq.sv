// UVM synthetic traffic sequence injecting random and permutation traffic into the 3D NoC mesh.
class noc_synthetic_seq extends uvm_sequence #(gridx_host_seq_item);
    `uvm_object_utils(noc_synthetic_seq)

    typedef enum { UNIFORM, HOTSPOT, TRANSPOSE, COMPLEMENT } traffic_pattern_e;
    traffic_pattern_e m_pattern = UNIFORM;
    int m_num_flits = 1000;

    function new(string name="noc_synthetic_seq");
        super.new(name);
    endfunction

    virtual task body();
        string pattern_str;
        int src_node, dst_node;
        int sx, sy, sz;
        int dx, dy, dz;

        if ($value$plusargs("TRAFFIC=%s", pattern_str)) begin
            if (pattern_str == "UNIFORM") m_pattern = UNIFORM;
            else if (pattern_str == "HOTSPOT") m_pattern = HOTSPOT;
            else if (pattern_str == "TRANSPOSE") m_pattern = TRANSPOSE;
            else if (pattern_str == "COMPLEMENT") m_pattern = COMPLEMENT;
        end

        `uvm_info("NOC_SEQ", $sformatf("Starting Synthetic NoC Traffic: %s (%0d flits)", m_pattern.name(), m_num_flits), UVM_LOW)

        for (int i = 0; i < m_num_flits; i++) begin
            gridx_host_seq_item txn;
            txn = gridx_host_seq_item::type_id::create("txn");

            src_node = $urandom_range(0, 63);
            sx = src_node % 4;
            sy = (src_node / 4) % 4;
            sz = src_node / 16;

            case (m_pattern)
                UNIFORM: begin
                    dst_node = $urandom_range(0, 63);
                end
                HOTSPOT: begin
                    dst_node = 12 + $urandom_range(0, 3);
                end
                TRANSPOSE: begin
                    dx = sy; dy = sx; dz = sz;
                    dst_node = (dz * 16) + (dy * 4) + dx;
                end
                COMPLEMENT: begin
                    dst_node = (~src_node) & 6'h3F;
                end
            endcase

            start_item(txn);
            txn.cmd_type = gridx_host_seq_item::CMD_WRITE_DMEM;
            txn.mem_addr = (dst_node << 16) | ($urandom & 16'hFFFF);
            txn.mem_data = $urandom;
            finish_item(txn);
        end

        `uvm_info("NOC_SEQ", "Completed Synthetic NoC Traffic", UVM_LOW)
    endtask
endclass
