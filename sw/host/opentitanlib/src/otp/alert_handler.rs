// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

use crate::otp::alert_handler_regs::*;
use crate::otp::lc_state::LcStateVal;
use crate::otp::otp_img::OtpRead;

use anyhow::{bail, Result};
use bitvec::prelude::*;
use crc::{Crc, Digest};
use num_enum::TryFromPrimitive;

use std::convert::TryFrom;

/// ALERT_HANDLER_ALERT_CLASS related register values.
#[derive(Clone, Copy, Debug, PartialEq)]
struct AlertClassRegs {
    regwen: u32,
    ctrl: u32,
    accum_thresh: u32,
    timeout_cyc: u32,
    phase_cycs: [u32; ALERT_HANDLER_PARAM_N_PHASES as usize],
}

/// Register values for alert_handler used in CRC32 calculation.
#[derive(Debug, PartialEq)]
pub struct AlertRegs {
    /// ALERT_HANDLER_LOC_ALERT_REGWEN
    regwen: [u32; ALERT_HANDLER_ALERT_REGWEN_MULTIREG_COUNT as usize],
    /// ALERT_HANDLER_ALERT_EN_SHADOWED
    en: [u32; ALERT_HANDLER_ALERT_EN_SHADOWED_MULTIREG_COUNT as usize],
    /// ALERT_HANDLER_ALERT_CLASS_SHADOWED
    class: [u32; ALERT_HANDLER_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize],
    /// ALERT_HANDLER_LOC_ALERT_REGWEN
    loc_regwen: [u32; ALERT_HANDLER_LOC_ALERT_REGWEN_MULTIREG_COUNT as usize],
    /// ALERT_HANDLER_LOC_ALERT_EN_SHADOWED
    loc_en: [u32; ALERT_HANDLER_LOC_ALERT_EN_SHADOWED_MULTIREG_COUNT as usize],
    /// ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED
    loc_class: [u32; ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize],
    /// Alert handler class registers
    class_regs: [AlertClassRegs; ALERT_HANDLER_PARAM_N_CLASSES as usize],
}

// TODO: Use bindgen to produce the following enum definitions.
/// Alert classification values.
///
/// Based on values generated by sparse-fsm-encode.py and defined in
/// sw/device/silicon_creator/lib/drivers/alert.h as alert_class_t.
#[derive(TryFromPrimitive)]
#[repr(u8)]
enum AlertClass {
    X = 0x94,
    A = 0xee,
    B = 0x64,
    C = 0xa7,
    D = 0x32,
}

impl AlertClass {
    fn index(&self) -> usize {
        match self {
            AlertClass::A => 0,
            AlertClass::B => 1,
            AlertClass::C => 2,
            AlertClass::D => 3,
            AlertClass::X => 0,
        }
    }

    fn from_index(index: usize) -> Self {
        match index {
            0 => AlertClass::A,
            1 => AlertClass::B,
            2 => AlertClass::C,
            3 => AlertClass::D,
            _ => AlertClass::X,
        }
    }
}

#[derive(TryFromPrimitive)]
#[repr(u8)]
enum AlertEnable {
    None = 0xa9,
    Enabled = 0x07,
    Locked = 0xd2,
}

#[derive(TryFromPrimitive)]
#[repr(u8)]
enum AlertEscalate {
    None = 0xd1,
    Phase0 = 0xb9,
    Phase1 = 0xcb,
    Phase2 = 0x25,
    Phase3 = 0x76,
}

struct AlertClassConfig {
    enabled: AlertEnable,
    escalate: AlertEscalate,
    accum_thresh: u32,
    timeout_cyc: u32,
    phase_cycs: [u32; ALERT_HANDLER_PARAM_N_PHASES as usize],
}

impl Default for AlertClassRegs {
    fn default() -> Self {
        AlertClassRegs {
            regwen: 1,
            ctrl: 0,
            accum_thresh: 0,
            timeout_cyc: 0,
            phase_cycs: [0; ALERT_HANDLER_PARAM_N_PHASES as usize],
        }
    }
}

impl Default for AlertRegs {
    fn default() -> Self {
        AlertRegs {
            regwen: [1; ALERT_HANDLER_ALERT_REGWEN_MULTIREG_COUNT as usize],
            loc_regwen: [1; ALERT_HANDLER_LOC_ALERT_REGWEN_MULTIREG_COUNT as usize],
            en: [0; ALERT_HANDLER_ALERT_EN_SHADOWED_MULTIREG_COUNT as usize],
            class: [0; ALERT_HANDLER_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize],
            loc_en: [0; ALERT_HANDLER_LOC_ALERT_EN_SHADOWED_MULTIREG_COUNT as usize],
            loc_class: [0; ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize],
            class_regs: [Default::default(); ALERT_HANDLER_PARAM_N_CLASSES as usize],
        }
    }
}

impl AlertRegs {
    /// Compute the CRC32 of the internal register values to match the value produced by
    /// `sw/device/silicon_creator/lib/drivers/alert.h:alert_config_crc32`.
    pub fn crc32(self) -> u32 {
        let crc = new_crc();
        let mut digest = crc.digest();
        self.crc32_add(&mut digest);
        digest.finalize()
    }

    /// Create the set of alert_handler register values from a given lifecycle state and OTP.
    ///
    /// The internal fields of `AlertRegs` should match those produced on the device after
    /// alert_handler is configured in `sw/lib/sw/device/silicon_creator/shutdown.h:shutdown_init`.
    pub fn try_new<T: OtpRead>(lc_state: LcStateVal, otp: &T) -> Result<Self> {
        let mut alert = AlertRegs::default();

        let lc_shift = match lc_state {
            LcStateVal::Prod => 0,
            LcStateVal::ProdEnd => 1,
            LcStateVal::Dev => 2,
            LcStateVal::Rma => 3,
            LcStateVal::Test => return Ok(alert),
        };

        let class_enable = otp.read32("OWNER_SW_CFG_ROM_ALERT_CLASS_EN")?;
        let class_escalate = otp.read32("OWNER_SW_CFG_ROM_ALERT_ESCALATION")?;

        for i in 0..ALERT_HANDLER_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize {
            let value = otp.read32_offset("OWNER_SW_CFG_ROM_ALERT_CLASSIFICATION", i * 4)?;
            let cls = AlertClass::try_from(value.to_le_bytes()[lc_shift])?;
            let enable = AlertEnable::try_from(class_enable.to_le_bytes()[cls.index()])?;
            alert.configure(i, cls, enable)?;
        }

        for i in 0..ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize {
            let value = otp.read32_offset("OWNER_SW_CFG_ROM_LOCAL_ALERT_CLASSIFICATION", i * 4)?;
            let cls = AlertClass::try_from(value.to_le_bytes()[lc_shift])?;
            let enable = AlertEnable::try_from(class_enable.to_le_bytes()[cls.index()])?;
            alert.local_configure(i, cls, enable)?;
        }

        for i in 0..ALERT_HANDLER_PARAM_N_CLASSES as usize {
            let mut phase_cycs = [0; ALERT_HANDLER_PARAM_N_PHASES as usize];
            for phase in 0..ALERT_HANDLER_PARAM_N_PHASES as usize {
                phase_cycs[phase] = otp.read32_offset(
                    "OWNER_SW_CFG_ROM_ALERT_PHASE_CYCLES",
                    (i * phase_cycs.len() + phase) * 4,
                )?;
            }
            let config = AlertClassConfig {
                enabled: AlertEnable::try_from(class_enable.to_le_bytes()[i])?,
                escalate: AlertEscalate::try_from(class_escalate.to_le_bytes()[i])?,
                accum_thresh: otp.read32_offset("OWNER_SW_CFG_ROM_ALERT_ACCUM_THRESH", i * 4)?,
                timeout_cyc: otp.read32_offset("OWNER_SW_CFG_ROM_ALERT_TIMEOUT_CYCLES", i * 4)?,
                phase_cycs,
            };
            alert.class_configure(AlertClass::from_index(i), &config)?;
        }

        Ok(alert)
    }

    fn configure(&mut self, index: usize, cls: AlertClass, enabled: AlertEnable) -> Result<()> {
        if index >= ALERT_HANDLER_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize {
            bail!("Bad alert index {}", index);
        }

        self.class[index] = match cls {
            AlertClass::A => ALERT_HANDLER_ALERT_CLASS_SHADOWED_0_CLASS_A_0_VALUE_CLASSA,
            AlertClass::B => ALERT_HANDLER_ALERT_CLASS_SHADOWED_0_CLASS_A_0_VALUE_CLASSB,
            AlertClass::C => ALERT_HANDLER_ALERT_CLASS_SHADOWED_0_CLASS_A_0_VALUE_CLASSC,
            AlertClass::D => ALERT_HANDLER_ALERT_CLASS_SHADOWED_0_CLASS_A_0_VALUE_CLASSD,
            AlertClass::X => return Ok(()),
        };

        match enabled {
            AlertEnable::None => {}
            AlertEnable::Enabled => self.en[index] = 1,
            AlertEnable::Locked => {
                self.en[index] = 1;
                self.regwen[index] = 0;
            }
        };

        Ok(())
    }

    fn local_configure(
        &mut self,
        index: usize,
        cls: AlertClass,
        enabled: AlertEnable,
    ) -> Result<()> {
        if index >= ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_MULTIREG_COUNT as usize {
            bail!("Bad local alert index {}", index);
        }

        self.loc_class[index] = match cls {
            AlertClass::A => ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_0_CLASS_LA_0_VALUE_CLASSA,
            AlertClass::B => ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_0_CLASS_LA_0_VALUE_CLASSB,
            AlertClass::C => ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_0_CLASS_LA_0_VALUE_CLASSC,
            AlertClass::D => ALERT_HANDLER_LOC_ALERT_CLASS_SHADOWED_0_CLASS_LA_0_VALUE_CLASSD,
            AlertClass::X => return Ok(()),
        };

        match enabled {
            AlertEnable::None => {}
            AlertEnable::Enabled => self.loc_en[index] = 1,
            AlertEnable::Locked => {
                self.loc_en[index] = 1;
                self.loc_regwen[index] = 0;
            }
        };

        Ok(())
    }

    fn class_configure(&mut self, cls: AlertClass, config: &AlertClassConfig) -> Result<()> {
        let index = match cls {
            AlertClass::A => 0,
            AlertClass::B => 1,
            AlertClass::C => 2,
            AlertClass::D => 3,
            AlertClass::X => bail!("Bad class"),
        };

        let mut reg = 0_u32;

        // TODO(lowRISC/opentitan#15443): Fix this lint (clippy::erasing_op):
        //reg |= (0 & ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E0_MASK)
        //    << ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E0_OFFSET;
        reg |= (1 & ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E1_MASK)
            << ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E1_OFFSET;
        reg |= (2 & ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E2_MASK)
            << ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E2_OFFSET;
        reg |= (3 & ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E3_MASK)
            << ALERT_HANDLER_CLASSA_CTRL_SHADOWED_MAP_E3_OFFSET;

        let reg_bits = reg.view_bits_mut::<Lsb0>();

        match config.enabled {
            AlertEnable::None => {}
            AlertEnable::Enabled => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_BIT as usize, true);
            }
            AlertEnable::Locked => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_LOCK_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_BIT as usize, true)
            }
        }

        match config.escalate {
            AlertEscalate::Phase0 => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E0_BIT as usize, true)
            }
            AlertEscalate::Phase1 => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E0_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E1_BIT as usize, true);
            }
            AlertEscalate::Phase2 => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E0_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E1_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E2_BIT as usize, true);
            }
            AlertEscalate::Phase3 => {
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E0_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E1_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E2_BIT as usize, true);
                reg_bits.set(ALERT_HANDLER_CLASSA_CTRL_SHADOWED_EN_E3_BIT as usize, true);
            }
            AlertEscalate::None => {}
        }

        self.class_regs[index].ctrl = reg;
        self.class_regs[index].accum_thresh = config.accum_thresh;
        self.class_regs[index].timeout_cyc = config.timeout_cyc;
        self.class_regs[index].phase_cycs = config.phase_cycs;

        Ok(())
    }
}

trait Crc32Add {
    fn crc32_add(self, diegst: &mut Digest<u32>);
}

impl Crc32Add for u32 {
    fn crc32_add(self, digest: &mut Digest<u32>) {
        digest.update(self.to_le_bytes().as_slice())
    }
}

impl<T: Crc32Add, const N: usize> Crc32Add for [T; N] {
    fn crc32_add(self, digest: &mut Digest<u32>) {
        self.map(|v| v.crc32_add(digest));
    }
}

impl Crc32Add for AlertClassRegs {
    fn crc32_add(self, digest: &mut Digest<u32>) {
        self.regwen.crc32_add(digest);
        self.ctrl.crc32_add(digest);
        self.accum_thresh.crc32_add(digest);
        self.timeout_cyc.crc32_add(digest);
        self.phase_cycs.crc32_add(digest);
    }
}

impl Crc32Add for AlertRegs {
    fn crc32_add(self, digest: &mut Digest<u32>) {
        self.regwen.crc32_add(digest);
        self.en.crc32_add(digest);
        self.class.crc32_add(digest);
        self.loc_regwen.crc32_add(digest);
        self.loc_en.crc32_add(digest);
        self.loc_class.crc32_add(digest);
        self.class_regs.crc32_add(digest);
    }
}

fn new_crc() -> Crc<u32> {
    Crc::<u32>::new(&crc::CRC_32_ISO_HDLC)
}

#[cfg(test)]
mod test {
    use super::*;

    // Register values dumped from device after alert_handler initialization.
    const TEST_REGS: AlertRegs = AlertRegs {
        regwen: [
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
        ],
        en: [
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        ],
        class: [
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        ],
        loc_regwen: [
            0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
        ],
        loc_en: [
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        ],
        loc_class: [
            0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        ],
        class_regs: [
            AlertClassRegs {
                regwen: 0x00000001,
                ctrl: 0x00003900,
                accum_thresh: 0x00000000,
                timeout_cyc: 0x00000000,
                phase_cycs: [0x00000000, 0x0000000a, 0x0000000a, 0xffffffff],
            },
            AlertClassRegs {
                regwen: 0x00000001,
                ctrl: 0x00003900,
                accum_thresh: 0x00000000,
                timeout_cyc: 0x00000000,
                phase_cycs: [0x00000000, 0x0000000a, 0x0000000a, 0xffffffff],
            },
            AlertClassRegs {
                regwen: 0x00000001,
                ctrl: 0x00003900,
                accum_thresh: 0x00000000,
                timeout_cyc: 0x00000000,
                phase_cycs: [0x00000000, 0x00000000, 0x00000000, 0x00000000],
            },
            AlertClassRegs {
                regwen: 0x00000001,
                ctrl: 0x00003900,
                accum_thresh: 0x00000000,
                timeout_cyc: 0x00000000,
                phase_cycs: [0x00000000, 0x00000000, 0x00000000, 0x00000000],
            },
        ],
    };

    struct TestOtpAlertsDisabled {}

    // OTP values that corrispond to the above `TEST_REG` values.
    impl OtpRead for TestOtpAlertsDisabled {
        fn read32_offset(&self, name: &str, offset: usize) -> Result<u32> {
            Ok(match name {
                "OWNER_SW_CFG_ROM_ALERT_CLASS_EN" => 0xa9a9a9a9,
                "OWNER_SW_CFG_ROM_ALERT_ESCALATION" => 0xd1d1d1d1,
                "OWNER_SW_CFG_ROM_ALERT_CLASSIFICATION"
                | "OWNER_SW_CFG_ROM_LOCAL_ALERT_CLASSIFICATION" => 0x94949494,
                "OWNER_SW_CFG_ROM_ALERT_PHASE_CYCLES" => [
                    0x00000000, 0x0000000a, 0x0000000a, 0xffffffff, // Class 0
                    0x00000000, 0x0000000a, 0x0000000a, 0xffffffff, // Class 1
                    0x00000000, 0x00000000, 0x00000000, 0x00000000, // Class 2
                    0x00000000, 0x00000000, 0x00000000, 0x00000000, // Class 3
                ][offset / 4],
                "OWNER_SW_CFG_ROM_ALERT_ACCUM_THRESH" | "OWNER_SW_CFG_ROM_ALERT_TIMEOUT_CYCLES" => {
                    0x00000000
                }
                _ => panic!("No such OTP value {}", name),
            })
        }
    }

    struct TestOtpAlertsEnabled {}

    // OTP values with `*_CLASS_EN` vales set to `kAlertEnableEnabled`
    impl OtpRead for TestOtpAlertsEnabled {
        fn read32_offset(&self, name: &str, offset: usize) -> Result<u32> {
            Ok(match name {
                "OWNER_SW_CFG_ROM_ALERT_CLASS_EN" => 0x07070707,
                "OWNER_SW_CFG_ROM_ALERT_ESCALATION" => 0xd1d1d1d1,
                "OWNER_SW_CFG_ROM_ALERT_CLASSIFICATION"
                | "OWNER_SW_CFG_ROM_LOCAL_ALERT_CLASSIFICATION" => 0x94949494,
                "OWNER_SW_CFG_ROM_ALERT_PHASE_CYCLES" => [
                    0x00000000, 0x0000000a, 0x0000000a, 0xffffffff, // Class 0
                    0x00000000, 0x0000000a, 0x0000000a, 0xffffffff, // Class 1
                    0x00000000, 0x00000000, 0x00000000, 0x00000000, // Class 2
                    0x00000000, 0x00000000, 0x00000000, 0x00000000, // Class 3
                ][offset / 4],
                "OWNER_SW_CFG_ROM_ALERT_ACCUM_THRESH" | "OWNER_SW_CFG_ROM_ALERT_TIMEOUT_CYCLES" => {
                    0x00000000
                }
                _ => panic!("No such OTP value {}", name),
            })
        }
    }

    // A sanity test to make sure the correct CRC algorithm is being used.
    //
    // These values are taken from the CRC32 unit tests in
    // `sw/lib/sw/device/silicon_creator/crc32_unittest.cc`.
    #[test]
    fn test_new_crc() {
        let crc = new_crc();
        let mut digest = crc.digest();
        digest.update(b"123456789");
        assert_eq!(digest.finalize(), 0xcbf43926);

        let crc = new_crc();
        let mut digest = crc.digest();
        digest.update(b"The quick brown fox jumps over the lazy dog");
        assert_eq!(digest.finalize(), 0x414fa339);

        let crc = new_crc();
        let mut digest = crc.digest();
        digest.update(b"\xfe\xca\xfe\xca\x02\xb0\xad\x1b");
        assert_eq!(digest.finalize(), 0x9508ac14);
    }

    #[test]
    fn test_crc_from_regs() {
        assert_eq!(TEST_REGS.crc32(), 0xE65FB2FF);
    }

    #[test]
    fn test_regs_from_otp() {
        assert_eq!(
            TEST_REGS,
            AlertRegs::try_new(LcStateVal::Dev, &TestOtpAlertsDisabled {}).unwrap()
        );
    }

    #[test]
    fn test_crc_disabled() {
        assert_eq!(
            AlertRegs::try_new(LcStateVal::Dev, &TestOtpAlertsDisabled {})
                .unwrap()
                .crc32(),
            0xE65FB2FF
        );
    }

    #[test]
    fn test_crc_enabled() {
        assert_eq!(
            AlertRegs::try_new(LcStateVal::Dev, &TestOtpAlertsEnabled {})
                .unwrap()
                .crc32(),
            0x492518C9
        );
    }
}
