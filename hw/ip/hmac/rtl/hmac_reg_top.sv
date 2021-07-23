// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Register Top module auto-generated by `reggen`

`include "prim_assert.sv"

module hmac_reg_top (
  input clk_i,
  input rst_ni,
  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  // Output port for window
  output tlul_pkg::tl_h2d_t tl_win_o,
  input  tlul_pkg::tl_d2h_t tl_win_i,

  // To HW
  output hmac_reg_pkg::hmac_reg2hw_t reg2hw, // Write
  input  hmac_reg_pkg::hmac_hw2reg_t hw2reg, // Read

  // Integrity check errors
  output logic intg_err_o,

  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);

  import hmac_reg_pkg::* ;

  localparam int AW = 12;
  localparam int DW = 32;
  localparam int DBW = DW/8;                    // Byte Width

  // register signals
  logic           reg_we;
  logic           reg_re;
  logic [AW-1:0]  reg_addr;
  logic [DW-1:0]  reg_wdata;
  logic [DBW-1:0] reg_be;
  logic [DW-1:0]  reg_rdata;
  logic           reg_error;

  logic          addrmiss, wr_err;

  logic [DW-1:0] reg_rdata_next;
  logic reg_busy;

  tlul_pkg::tl_h2d_t tl_reg_h2d;
  tlul_pkg::tl_d2h_t tl_reg_d2h;


  // incoming payload check
  logic intg_err;
  tlul_cmd_intg_chk u_chk (
    .tl_i(tl_i),
    .err_o(intg_err)
  );

  logic intg_err_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      intg_err_q <= '0;
    end else if (intg_err) begin
      intg_err_q <= 1'b1;
    end
  end

  // integrity error output is permanent and should be used for alert generation
  // register errors are transactional
  assign intg_err_o = intg_err_q | intg_err;

  // outgoing integrity generation
  tlul_pkg::tl_d2h_t tl_o_pre;
  tlul_rsp_intg_gen #(
    .EnableRspIntgGen(1),
    .EnableDataIntgGen(1)
  ) u_rsp_intg_gen (
    .tl_i(tl_o_pre),
    .tl_o(tl_o)
  );

  tlul_pkg::tl_h2d_t tl_socket_h2d [2];
  tlul_pkg::tl_d2h_t tl_socket_d2h [2];

  logic [1:0] reg_steer;

  // socket_1n connection
  assign tl_reg_h2d = tl_socket_h2d[1];
  assign tl_socket_d2h[1] = tl_reg_d2h;

  assign tl_win_o = tl_socket_h2d[0];
  assign tl_socket_d2h[0] = tl_win_i;

  // Create Socket_1n
  tlul_socket_1n #(
    .N          (2),
    .HReqPass   (1'b1),
    .HRspPass   (1'b1),
    .DReqPass   ({2{1'b1}}),
    .DRspPass   ({2{1'b1}}),
    .HReqDepth  (4'h0),
    .HRspDepth  (4'h0),
    .DReqDepth  ({2{4'h0}}),
    .DRspDepth  ({2{4'h0}})
  ) u_socket (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .tl_h_i (tl_i),
    .tl_h_o (tl_o_pre),
    .tl_d_o (tl_socket_h2d),
    .tl_d_i (tl_socket_d2h),
    .dev_select_i (reg_steer)
  );

  // Create steering logic
  always_comb begin
    reg_steer = 1;       // Default set to register

    // TODO: Can below codes be unique case () inside ?
    if (tl_i.a_address[AW-1:0] >= 2048) begin
      reg_steer = 0;
    end
    if (intg_err) begin
      reg_steer = 1;
    end
  end

  tlul_adapter_reg #(
    .RegAw(AW),
    .RegDw(DW),
    .EnableDataIntgGen(0)
  ) u_reg_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .tl_i (tl_reg_h2d),
    .tl_o (tl_reg_d2h),

    .we_o    (reg_we),
    .re_o    (reg_re),
    .addr_o  (reg_addr),
    .wdata_o (reg_wdata),
    .be_o    (reg_be),
    .busy_i  (reg_busy),
    .rdata_i (reg_rdata),
    .error_i (reg_error)
  );

  // cdc oversampling signals

  assign reg_rdata = reg_rdata_next ;
  assign reg_error = (devmode_i & addrmiss) | wr_err | intg_err;

  // Define SW related signals
  // Format: <reg>_<field>_{wd|we|qs}
  //        or <reg>_{wd|we|qs} if field == 1 or 0
  logic intr_state_we;
  logic intr_state_hmac_done_qs;
  logic intr_state_hmac_done_wd;
  logic intr_state_fifo_empty_qs;
  logic intr_state_fifo_empty_wd;
  logic intr_state_hmac_err_qs;
  logic intr_state_hmac_err_wd;
  logic intr_enable_we;
  logic intr_enable_hmac_done_qs;
  logic intr_enable_hmac_done_wd;
  logic intr_enable_fifo_empty_qs;
  logic intr_enable_fifo_empty_wd;
  logic intr_enable_hmac_err_qs;
  logic intr_enable_hmac_err_wd;
  logic intr_test_we;
  logic intr_test_hmac_done_wd;
  logic intr_test_fifo_empty_wd;
  logic intr_test_hmac_err_wd;
  logic alert_test_we;
  logic alert_test_wd;
  logic cfg_re;
  logic cfg_we;
  logic cfg_hmac_en_qs;
  logic cfg_hmac_en_wd;
  logic cfg_sha_en_qs;
  logic cfg_sha_en_wd;
  logic cfg_endian_swap_qs;
  logic cfg_endian_swap_wd;
  logic cfg_digest_swap_qs;
  logic cfg_digest_swap_wd;
  logic cmd_we;
  logic cmd_hash_start_wd;
  logic cmd_hash_process_wd;
  logic status_re;
  logic status_fifo_empty_qs;
  logic status_fifo_full_qs;
  logic [4:0] status_fifo_depth_qs;
  logic [31:0] err_code_qs;
  logic wipe_secret_we;
  logic [31:0] wipe_secret_wd;
  logic key_0_we;
  logic [31:0] key_0_wd;
  logic key_1_we;
  logic [31:0] key_1_wd;
  logic key_2_we;
  logic [31:0] key_2_wd;
  logic key_3_we;
  logic [31:0] key_3_wd;
  logic key_4_we;
  logic [31:0] key_4_wd;
  logic key_5_we;
  logic [31:0] key_5_wd;
  logic key_6_we;
  logic [31:0] key_6_wd;
  logic key_7_we;
  logic [31:0] key_7_wd;
  logic digest_0_re;
  logic [31:0] digest_0_qs;
  logic digest_1_re;
  logic [31:0] digest_1_qs;
  logic digest_2_re;
  logic [31:0] digest_2_qs;
  logic digest_3_re;
  logic [31:0] digest_3_qs;
  logic digest_4_re;
  logic [31:0] digest_4_qs;
  logic digest_5_re;
  logic [31:0] digest_5_qs;
  logic digest_6_re;
  logic [31:0] digest_6_qs;
  logic digest_7_re;
  logic [31:0] digest_7_qs;
  logic [31:0] msg_length_lower_qs;
  logic [31:0] msg_length_upper_qs;

  // Register instances
  // R[intr_state]: V(False)

  //   F[hmac_done]: 0:0
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessW1C),
    .RESVAL  (1'h0)
  ) u_intr_state_hmac_done (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_state_we),
    .wd     (intr_state_hmac_done_wd),

    // from internal hardware
    .de     (hw2reg.intr_state.hmac_done.de),
    .d      (hw2reg.intr_state.hmac_done.d),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_state.hmac_done.q),

    // to register interface (read)
    .qs     (intr_state_hmac_done_qs)
  );


  //   F[fifo_empty]: 1:1
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessW1C),
    .RESVAL  (1'h0)
  ) u_intr_state_fifo_empty (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_state_we),
    .wd     (intr_state_fifo_empty_wd),

    // from internal hardware
    .de     (hw2reg.intr_state.fifo_empty.de),
    .d      (hw2reg.intr_state.fifo_empty.d),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_state.fifo_empty.q),

    // to register interface (read)
    .qs     (intr_state_fifo_empty_qs)
  );


  //   F[hmac_err]: 2:2
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessW1C),
    .RESVAL  (1'h0)
  ) u_intr_state_hmac_err (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_state_we),
    .wd     (intr_state_hmac_err_wd),

    // from internal hardware
    .de     (hw2reg.intr_state.hmac_err.de),
    .d      (hw2reg.intr_state.hmac_err.d),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_state.hmac_err.q),

    // to register interface (read)
    .qs     (intr_state_hmac_err_qs)
  );


  // R[intr_enable]: V(False)

  //   F[hmac_done]: 0:0
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessRW),
    .RESVAL  (1'h0)
  ) u_intr_enable_hmac_done (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_enable_we),
    .wd     (intr_enable_hmac_done_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_enable.hmac_done.q),

    // to register interface (read)
    .qs     (intr_enable_hmac_done_qs)
  );


  //   F[fifo_empty]: 1:1
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessRW),
    .RESVAL  (1'h0)
  ) u_intr_enable_fifo_empty (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_enable_we),
    .wd     (intr_enable_fifo_empty_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_enable.fifo_empty.q),

    // to register interface (read)
    .qs     (intr_enable_fifo_empty_qs)
  );


  //   F[hmac_err]: 2:2
  prim_subreg #(
    .DW      (1),
    .SwAccess(prim_subreg_pkg::SwAccessRW),
    .RESVAL  (1'h0)
  ) u_intr_enable_hmac_err (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (intr_enable_we),
    .wd     (intr_enable_hmac_err_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.intr_enable.hmac_err.q),

    // to register interface (read)
    .qs     (intr_enable_hmac_err_qs)
  );


  // R[intr_test]: V(True)

  //   F[hmac_done]: 0:0
  prim_subreg_ext #(
    .DW    (1)
  ) u_intr_test_hmac_done (
    .re     (1'b0),
    .we     (intr_test_we),
    .wd     (intr_test_hmac_done_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.intr_test.hmac_done.qe),
    .q      (reg2hw.intr_test.hmac_done.q),
    .qs     ()
  );


  //   F[fifo_empty]: 1:1
  prim_subreg_ext #(
    .DW    (1)
  ) u_intr_test_fifo_empty (
    .re     (1'b0),
    .we     (intr_test_we),
    .wd     (intr_test_fifo_empty_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.intr_test.fifo_empty.qe),
    .q      (reg2hw.intr_test.fifo_empty.q),
    .qs     ()
  );


  //   F[hmac_err]: 2:2
  prim_subreg_ext #(
    .DW    (1)
  ) u_intr_test_hmac_err (
    .re     (1'b0),
    .we     (intr_test_we),
    .wd     (intr_test_hmac_err_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.intr_test.hmac_err.qe),
    .q      (reg2hw.intr_test.hmac_err.q),
    .qs     ()
  );


  // R[alert_test]: V(True)

  prim_subreg_ext #(
    .DW    (1)
  ) u_alert_test (
    .re     (1'b0),
    .we     (alert_test_we),
    .wd     (alert_test_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.alert_test.qe),
    .q      (reg2hw.alert_test.q),
    .qs     ()
  );


  // R[cfg]: V(True)

  //   F[hmac_en]: 0:0
  prim_subreg_ext #(
    .DW    (1)
  ) u_cfg_hmac_en (
    .re     (cfg_re),
    .we     (cfg_we),
    .wd     (cfg_hmac_en_wd),
    .d      (hw2reg.cfg.hmac_en.d),
    .qre    (),
    .qe     (reg2hw.cfg.hmac_en.qe),
    .q      (reg2hw.cfg.hmac_en.q),
    .qs     (cfg_hmac_en_qs)
  );


  //   F[sha_en]: 1:1
  prim_subreg_ext #(
    .DW    (1)
  ) u_cfg_sha_en (
    .re     (cfg_re),
    .we     (cfg_we),
    .wd     (cfg_sha_en_wd),
    .d      (hw2reg.cfg.sha_en.d),
    .qre    (),
    .qe     (reg2hw.cfg.sha_en.qe),
    .q      (reg2hw.cfg.sha_en.q),
    .qs     (cfg_sha_en_qs)
  );


  //   F[endian_swap]: 2:2
  prim_subreg_ext #(
    .DW    (1)
  ) u_cfg_endian_swap (
    .re     (cfg_re),
    .we     (cfg_we),
    .wd     (cfg_endian_swap_wd),
    .d      (hw2reg.cfg.endian_swap.d),
    .qre    (),
    .qe     (reg2hw.cfg.endian_swap.qe),
    .q      (reg2hw.cfg.endian_swap.q),
    .qs     (cfg_endian_swap_qs)
  );


  //   F[digest_swap]: 3:3
  prim_subreg_ext #(
    .DW    (1)
  ) u_cfg_digest_swap (
    .re     (cfg_re),
    .we     (cfg_we),
    .wd     (cfg_digest_swap_wd),
    .d      (hw2reg.cfg.digest_swap.d),
    .qre    (),
    .qe     (reg2hw.cfg.digest_swap.qe),
    .q      (reg2hw.cfg.digest_swap.q),
    .qs     (cfg_digest_swap_qs)
  );


  // R[cmd]: V(True)

  //   F[hash_start]: 0:0
  prim_subreg_ext #(
    .DW    (1)
  ) u_cmd_hash_start (
    .re     (1'b0),
    .we     (cmd_we),
    .wd     (cmd_hash_start_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.cmd.hash_start.qe),
    .q      (reg2hw.cmd.hash_start.q),
    .qs     ()
  );


  //   F[hash_process]: 1:1
  prim_subreg_ext #(
    .DW    (1)
  ) u_cmd_hash_process (
    .re     (1'b0),
    .we     (cmd_we),
    .wd     (cmd_hash_process_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.cmd.hash_process.qe),
    .q      (reg2hw.cmd.hash_process.q),
    .qs     ()
  );


  // R[status]: V(True)

  //   F[fifo_empty]: 0:0
  prim_subreg_ext #(
    .DW    (1)
  ) u_status_fifo_empty (
    .re     (status_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.status.fifo_empty.d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (status_fifo_empty_qs)
  );


  //   F[fifo_full]: 1:1
  prim_subreg_ext #(
    .DW    (1)
  ) u_status_fifo_full (
    .re     (status_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.status.fifo_full.d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (status_fifo_full_qs)
  );


  //   F[fifo_depth]: 8:4
  prim_subreg_ext #(
    .DW    (5)
  ) u_status_fifo_depth (
    .re     (status_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.status.fifo_depth.d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (status_fifo_depth_qs)
  );


  // R[err_code]: V(False)

  prim_subreg #(
    .DW      (32),
    .SwAccess(prim_subreg_pkg::SwAccessRO),
    .RESVAL  (32'h0)
  ) u_err_code (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (1'b0),
    .wd     ('0),

    // from internal hardware
    .de     (hw2reg.err_code.de),
    .d      (hw2reg.err_code.d),

    // to internal hardware
    .qe     (),
    .q      (),

    // to register interface (read)
    .qs     (err_code_qs)
  );


  // R[wipe_secret]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_wipe_secret (
    .re     (1'b0),
    .we     (wipe_secret_we),
    .wd     (wipe_secret_wd),
    .d      ('0),
    .qre    (),
    .qe     (reg2hw.wipe_secret.qe),
    .q      (reg2hw.wipe_secret.q),
    .qs     ()
  );



  // Subregister 0 of Multireg key
  // R[key_0]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_0 (
    .re     (1'b0),
    .we     (key_0_we),
    .wd     (key_0_wd),
    .d      (hw2reg.key[0].d),
    .qre    (),
    .qe     (reg2hw.key[0].qe),
    .q      (reg2hw.key[0].q),
    .qs     ()
  );

  // Subregister 1 of Multireg key
  // R[key_1]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_1 (
    .re     (1'b0),
    .we     (key_1_we),
    .wd     (key_1_wd),
    .d      (hw2reg.key[1].d),
    .qre    (),
    .qe     (reg2hw.key[1].qe),
    .q      (reg2hw.key[1].q),
    .qs     ()
  );

  // Subregister 2 of Multireg key
  // R[key_2]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_2 (
    .re     (1'b0),
    .we     (key_2_we),
    .wd     (key_2_wd),
    .d      (hw2reg.key[2].d),
    .qre    (),
    .qe     (reg2hw.key[2].qe),
    .q      (reg2hw.key[2].q),
    .qs     ()
  );

  // Subregister 3 of Multireg key
  // R[key_3]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_3 (
    .re     (1'b0),
    .we     (key_3_we),
    .wd     (key_3_wd),
    .d      (hw2reg.key[3].d),
    .qre    (),
    .qe     (reg2hw.key[3].qe),
    .q      (reg2hw.key[3].q),
    .qs     ()
  );

  // Subregister 4 of Multireg key
  // R[key_4]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_4 (
    .re     (1'b0),
    .we     (key_4_we),
    .wd     (key_4_wd),
    .d      (hw2reg.key[4].d),
    .qre    (),
    .qe     (reg2hw.key[4].qe),
    .q      (reg2hw.key[4].q),
    .qs     ()
  );

  // Subregister 5 of Multireg key
  // R[key_5]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_5 (
    .re     (1'b0),
    .we     (key_5_we),
    .wd     (key_5_wd),
    .d      (hw2reg.key[5].d),
    .qre    (),
    .qe     (reg2hw.key[5].qe),
    .q      (reg2hw.key[5].q),
    .qs     ()
  );

  // Subregister 6 of Multireg key
  // R[key_6]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_6 (
    .re     (1'b0),
    .we     (key_6_we),
    .wd     (key_6_wd),
    .d      (hw2reg.key[6].d),
    .qre    (),
    .qe     (reg2hw.key[6].qe),
    .q      (reg2hw.key[6].q),
    .qs     ()
  );

  // Subregister 7 of Multireg key
  // R[key_7]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_key_7 (
    .re     (1'b0),
    .we     (key_7_we),
    .wd     (key_7_wd),
    .d      (hw2reg.key[7].d),
    .qre    (),
    .qe     (reg2hw.key[7].qe),
    .q      (reg2hw.key[7].q),
    .qs     ()
  );



  // Subregister 0 of Multireg digest
  // R[digest_0]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_0 (
    .re     (digest_0_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[0].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_0_qs)
  );

  // Subregister 1 of Multireg digest
  // R[digest_1]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_1 (
    .re     (digest_1_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[1].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_1_qs)
  );

  // Subregister 2 of Multireg digest
  // R[digest_2]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_2 (
    .re     (digest_2_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[2].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_2_qs)
  );

  // Subregister 3 of Multireg digest
  // R[digest_3]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_3 (
    .re     (digest_3_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[3].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_3_qs)
  );

  // Subregister 4 of Multireg digest
  // R[digest_4]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_4 (
    .re     (digest_4_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[4].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_4_qs)
  );

  // Subregister 5 of Multireg digest
  // R[digest_5]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_5 (
    .re     (digest_5_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[5].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_5_qs)
  );

  // Subregister 6 of Multireg digest
  // R[digest_6]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_6 (
    .re     (digest_6_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[6].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_6_qs)
  );

  // Subregister 7 of Multireg digest
  // R[digest_7]: V(True)

  prim_subreg_ext #(
    .DW    (32)
  ) u_digest_7 (
    .re     (digest_7_re),
    .we     (1'b0),
    .wd     ('0),
    .d      (hw2reg.digest[7].d),
    .qre    (),
    .qe     (),
    .q      (),
    .qs     (digest_7_qs)
  );


  // R[msg_length_lower]: V(False)

  prim_subreg #(
    .DW      (32),
    .SwAccess(prim_subreg_pkg::SwAccessRO),
    .RESVAL  (32'h0)
  ) u_msg_length_lower (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (1'b0),
    .wd     ('0),

    // from internal hardware
    .de     (hw2reg.msg_length_lower.de),
    .d      (hw2reg.msg_length_lower.d),

    // to internal hardware
    .qe     (),
    .q      (),

    // to register interface (read)
    .qs     (msg_length_lower_qs)
  );


  // R[msg_length_upper]: V(False)

  prim_subreg #(
    .DW      (32),
    .SwAccess(prim_subreg_pkg::SwAccessRO),
    .RESVAL  (32'h0)
  ) u_msg_length_upper (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),

    // from register interface
    .we     (1'b0),
    .wd     ('0),

    // from internal hardware
    .de     (hw2reg.msg_length_upper.de),
    .d      (hw2reg.msg_length_upper.d),

    // to internal hardware
    .qe     (),
    .q      (),

    // to register interface (read)
    .qs     (msg_length_upper_qs)
  );




  logic [26:0] addr_hit;
  always_comb begin
    addr_hit = '0;
    addr_hit[ 0] = (reg_addr == HMAC_INTR_STATE_OFFSET);
    addr_hit[ 1] = (reg_addr == HMAC_INTR_ENABLE_OFFSET);
    addr_hit[ 2] = (reg_addr == HMAC_INTR_TEST_OFFSET);
    addr_hit[ 3] = (reg_addr == HMAC_ALERT_TEST_OFFSET);
    addr_hit[ 4] = (reg_addr == HMAC_CFG_OFFSET);
    addr_hit[ 5] = (reg_addr == HMAC_CMD_OFFSET);
    addr_hit[ 6] = (reg_addr == HMAC_STATUS_OFFSET);
    addr_hit[ 7] = (reg_addr == HMAC_ERR_CODE_OFFSET);
    addr_hit[ 8] = (reg_addr == HMAC_WIPE_SECRET_OFFSET);
    addr_hit[ 9] = (reg_addr == HMAC_KEY_0_OFFSET);
    addr_hit[10] = (reg_addr == HMAC_KEY_1_OFFSET);
    addr_hit[11] = (reg_addr == HMAC_KEY_2_OFFSET);
    addr_hit[12] = (reg_addr == HMAC_KEY_3_OFFSET);
    addr_hit[13] = (reg_addr == HMAC_KEY_4_OFFSET);
    addr_hit[14] = (reg_addr == HMAC_KEY_5_OFFSET);
    addr_hit[15] = (reg_addr == HMAC_KEY_6_OFFSET);
    addr_hit[16] = (reg_addr == HMAC_KEY_7_OFFSET);
    addr_hit[17] = (reg_addr == HMAC_DIGEST_0_OFFSET);
    addr_hit[18] = (reg_addr == HMAC_DIGEST_1_OFFSET);
    addr_hit[19] = (reg_addr == HMAC_DIGEST_2_OFFSET);
    addr_hit[20] = (reg_addr == HMAC_DIGEST_3_OFFSET);
    addr_hit[21] = (reg_addr == HMAC_DIGEST_4_OFFSET);
    addr_hit[22] = (reg_addr == HMAC_DIGEST_5_OFFSET);
    addr_hit[23] = (reg_addr == HMAC_DIGEST_6_OFFSET);
    addr_hit[24] = (reg_addr == HMAC_DIGEST_7_OFFSET);
    addr_hit[25] = (reg_addr == HMAC_MSG_LENGTH_LOWER_OFFSET);
    addr_hit[26] = (reg_addr == HMAC_MSG_LENGTH_UPPER_OFFSET);
  end

  assign addrmiss = (reg_re || reg_we) ? ~|addr_hit : 1'b0 ;

  // Check sub-word write is permitted
  always_comb begin
    wr_err = (reg_we &
              ((addr_hit[ 0] & (|(HMAC_PERMIT[ 0] & ~reg_be))) |
               (addr_hit[ 1] & (|(HMAC_PERMIT[ 1] & ~reg_be))) |
               (addr_hit[ 2] & (|(HMAC_PERMIT[ 2] & ~reg_be))) |
               (addr_hit[ 3] & (|(HMAC_PERMIT[ 3] & ~reg_be))) |
               (addr_hit[ 4] & (|(HMAC_PERMIT[ 4] & ~reg_be))) |
               (addr_hit[ 5] & (|(HMAC_PERMIT[ 5] & ~reg_be))) |
               (addr_hit[ 6] & (|(HMAC_PERMIT[ 6] & ~reg_be))) |
               (addr_hit[ 7] & (|(HMAC_PERMIT[ 7] & ~reg_be))) |
               (addr_hit[ 8] & (|(HMAC_PERMIT[ 8] & ~reg_be))) |
               (addr_hit[ 9] & (|(HMAC_PERMIT[ 9] & ~reg_be))) |
               (addr_hit[10] & (|(HMAC_PERMIT[10] & ~reg_be))) |
               (addr_hit[11] & (|(HMAC_PERMIT[11] & ~reg_be))) |
               (addr_hit[12] & (|(HMAC_PERMIT[12] & ~reg_be))) |
               (addr_hit[13] & (|(HMAC_PERMIT[13] & ~reg_be))) |
               (addr_hit[14] & (|(HMAC_PERMIT[14] & ~reg_be))) |
               (addr_hit[15] & (|(HMAC_PERMIT[15] & ~reg_be))) |
               (addr_hit[16] & (|(HMAC_PERMIT[16] & ~reg_be))) |
               (addr_hit[17] & (|(HMAC_PERMIT[17] & ~reg_be))) |
               (addr_hit[18] & (|(HMAC_PERMIT[18] & ~reg_be))) |
               (addr_hit[19] & (|(HMAC_PERMIT[19] & ~reg_be))) |
               (addr_hit[20] & (|(HMAC_PERMIT[20] & ~reg_be))) |
               (addr_hit[21] & (|(HMAC_PERMIT[21] & ~reg_be))) |
               (addr_hit[22] & (|(HMAC_PERMIT[22] & ~reg_be))) |
               (addr_hit[23] & (|(HMAC_PERMIT[23] & ~reg_be))) |
               (addr_hit[24] & (|(HMAC_PERMIT[24] & ~reg_be))) |
               (addr_hit[25] & (|(HMAC_PERMIT[25] & ~reg_be))) |
               (addr_hit[26] & (|(HMAC_PERMIT[26] & ~reg_be)))));
  end
  assign intr_state_we = addr_hit[0] & reg_we & !reg_error;

  assign intr_state_hmac_done_wd = reg_wdata[0];

  assign intr_state_fifo_empty_wd = reg_wdata[1];

  assign intr_state_hmac_err_wd = reg_wdata[2];
  assign intr_enable_we = addr_hit[1] & reg_we & !reg_error;

  assign intr_enable_hmac_done_wd = reg_wdata[0];

  assign intr_enable_fifo_empty_wd = reg_wdata[1];

  assign intr_enable_hmac_err_wd = reg_wdata[2];
  assign intr_test_we = addr_hit[2] & reg_we & !reg_error;

  assign intr_test_hmac_done_wd = reg_wdata[0];

  assign intr_test_fifo_empty_wd = reg_wdata[1];

  assign intr_test_hmac_err_wd = reg_wdata[2];
  assign alert_test_we = addr_hit[3] & reg_we & !reg_error;

  assign alert_test_wd = reg_wdata[0];
  assign cfg_re = addr_hit[4] & reg_re & !reg_error;
  assign cfg_we = addr_hit[4] & reg_we & !reg_error;

  assign cfg_hmac_en_wd = reg_wdata[0];

  assign cfg_sha_en_wd = reg_wdata[1];

  assign cfg_endian_swap_wd = reg_wdata[2];

  assign cfg_digest_swap_wd = reg_wdata[3];
  assign cmd_we = addr_hit[5] & reg_we & !reg_error;

  assign cmd_hash_start_wd = reg_wdata[0];

  assign cmd_hash_process_wd = reg_wdata[1];
  assign status_re = addr_hit[6] & reg_re & !reg_error;
  assign wipe_secret_we = addr_hit[8] & reg_we & !reg_error;

  assign wipe_secret_wd = reg_wdata[31:0];
  assign key_0_we = addr_hit[9] & reg_we & !reg_error;

  assign key_0_wd = reg_wdata[31:0];
  assign key_1_we = addr_hit[10] & reg_we & !reg_error;

  assign key_1_wd = reg_wdata[31:0];
  assign key_2_we = addr_hit[11] & reg_we & !reg_error;

  assign key_2_wd = reg_wdata[31:0];
  assign key_3_we = addr_hit[12] & reg_we & !reg_error;

  assign key_3_wd = reg_wdata[31:0];
  assign key_4_we = addr_hit[13] & reg_we & !reg_error;

  assign key_4_wd = reg_wdata[31:0];
  assign key_5_we = addr_hit[14] & reg_we & !reg_error;

  assign key_5_wd = reg_wdata[31:0];
  assign key_6_we = addr_hit[15] & reg_we & !reg_error;

  assign key_6_wd = reg_wdata[31:0];
  assign key_7_we = addr_hit[16] & reg_we & !reg_error;

  assign key_7_wd = reg_wdata[31:0];
  assign digest_0_re = addr_hit[17] & reg_re & !reg_error;
  assign digest_1_re = addr_hit[18] & reg_re & !reg_error;
  assign digest_2_re = addr_hit[19] & reg_re & !reg_error;
  assign digest_3_re = addr_hit[20] & reg_re & !reg_error;
  assign digest_4_re = addr_hit[21] & reg_re & !reg_error;
  assign digest_5_re = addr_hit[22] & reg_re & !reg_error;
  assign digest_6_re = addr_hit[23] & reg_re & !reg_error;
  assign digest_7_re = addr_hit[24] & reg_re & !reg_error;

  // Read data return
  always_comb begin
    reg_rdata_next = '0;
    unique case (1'b1)
      addr_hit[0]: begin
        reg_rdata_next[0] = intr_state_hmac_done_qs;
        reg_rdata_next[1] = intr_state_fifo_empty_qs;
        reg_rdata_next[2] = intr_state_hmac_err_qs;
      end

      addr_hit[1]: begin
        reg_rdata_next[0] = intr_enable_hmac_done_qs;
        reg_rdata_next[1] = intr_enable_fifo_empty_qs;
        reg_rdata_next[2] = intr_enable_hmac_err_qs;
      end

      addr_hit[2]: begin
        reg_rdata_next[0] = '0;
        reg_rdata_next[1] = '0;
        reg_rdata_next[2] = '0;
      end

      addr_hit[3]: begin
        reg_rdata_next[0] = '0;
      end

      addr_hit[4]: begin
        reg_rdata_next[0] = cfg_hmac_en_qs;
        reg_rdata_next[1] = cfg_sha_en_qs;
        reg_rdata_next[2] = cfg_endian_swap_qs;
        reg_rdata_next[3] = cfg_digest_swap_qs;
      end

      addr_hit[5]: begin
        reg_rdata_next[0] = '0;
        reg_rdata_next[1] = '0;
      end

      addr_hit[6]: begin
        reg_rdata_next[0] = status_fifo_empty_qs;
        reg_rdata_next[1] = status_fifo_full_qs;
        reg_rdata_next[8:4] = status_fifo_depth_qs;
      end

      addr_hit[7]: begin
        reg_rdata_next[31:0] = err_code_qs;
      end

      addr_hit[8]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[9]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[10]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[11]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[12]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[13]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[14]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[15]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[16]: begin
        reg_rdata_next[31:0] = '0;
      end

      addr_hit[17]: begin
        reg_rdata_next[31:0] = digest_0_qs;
      end

      addr_hit[18]: begin
        reg_rdata_next[31:0] = digest_1_qs;
      end

      addr_hit[19]: begin
        reg_rdata_next[31:0] = digest_2_qs;
      end

      addr_hit[20]: begin
        reg_rdata_next[31:0] = digest_3_qs;
      end

      addr_hit[21]: begin
        reg_rdata_next[31:0] = digest_4_qs;
      end

      addr_hit[22]: begin
        reg_rdata_next[31:0] = digest_5_qs;
      end

      addr_hit[23]: begin
        reg_rdata_next[31:0] = digest_6_qs;
      end

      addr_hit[24]: begin
        reg_rdata_next[31:0] = digest_7_qs;
      end

      addr_hit[25]: begin
        reg_rdata_next[31:0] = msg_length_lower_qs;
      end

      addr_hit[26]: begin
        reg_rdata_next[31:0] = msg_length_upper_qs;
      end

      default: begin
        reg_rdata_next = '1;
      end
    endcase
  end

  // shadow busy
  logic shadow_busy;
  assign shadow_busy = 1'b0;

  // register busy
  logic reg_busy_sel;
  assign reg_busy = reg_busy_sel | shadow_busy;
  always_comb begin
    reg_busy_sel = '0;
    unique case (1'b1)
      default: begin
        reg_busy_sel  = '0;
      end
    endcase
  end



  // Unused signal tieoff

  // wdata / byte enable are not always fully used
  // add a blanket unused statement to handle lint waivers
  logic unused_wdata;
  logic unused_be;
  assign unused_wdata = ^reg_wdata;
  assign unused_be = ^reg_be;

  // Assertions for Register Interface
  `ASSERT_PULSE(wePulse, reg_we, clk_i, !rst_ni)
  `ASSERT_PULSE(rePulse, reg_re, clk_i, !rst_ni)

  `ASSERT(reAfterRv, $rose(reg_re || reg_we) |=> tl_o_pre.d_valid, clk_i, !rst_ni)

  `ASSERT(en2addrHit, (reg_we || reg_re) |-> $onehot0(addr_hit), clk_i, !rst_ni)

  // this is formulated as an assumption such that the FPV testbenches do disprove this
  // property by mistake
  //`ASSUME(reqParity, tl_reg_h2d.a_valid |-> tl_reg_h2d.a_user.chk_en == tlul_pkg::CheckDis)

endmodule
