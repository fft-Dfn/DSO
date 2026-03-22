
// Efinity Top-level template
// Version: 2025.2.288.3.8
// Date: 2026-03-22 22:04

// Copyright (C) 2013 - 2025 Efinix Inc. All rights reserved.

// This file may be used as a starting point for Efinity synthesis top-level target.
// The port list here matches what is expected by Efinity constraint files generated
// by the Efinity Interface Designer.

// To use this:
//     #1)  Save this file with a different name to a different directory, where source files are kept.
//              Example: you may wish to save as DSO_project.v
//     #2)  Add the newly saved file into Efinity project as design file
//     #3)  Edit the top level entity in Efinity project to:  DSO_project
//     #4)  Insert design content.


module DSO_project
(
  (* syn_peri_port = 0 *) input clk_50m,
  (* syn_peri_port = 0 *) input key_back_n,
  (* syn_peri_port = 0 *) input key_down_n,
  (* syn_peri_port = 0 *) input key_enter_n,
  (* syn_peri_port = 0 *) input key_up_n,
  (* syn_peri_port = 0 *) input sys_rst_n,
  (* syn_peri_port = 0 *) input pll_locked,
  (* syn_peri_port = 0 *) input clk_25m,
  (* syn_peri_port = 0 *) output [4:0] vga_b,
  (* syn_peri_port = 0 *) output [5:0] vga_g,
  (* syn_peri_port = 0 *) output vga_hs,
  (* syn_peri_port = 0 *) output [4:0] vga_r,
  (* syn_peri_port = 0 *) output vga_vs,
  (* syn_peri_port = 0 *) output led_0
);


endmodule

