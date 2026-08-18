/// Every asset in the TS §7.1 manifest.
enum SfxId {
  squelchOpen('squelch_open'),
  squelchTail('squelch_tail'),
  staticBed1('static_bed_1'),
  staticBed2('static_bed_2'),
  staticBed3('static_bed_3'),
  tuneBurst('tune_burst'),
  scanTick('scan_tick'),
  rogerK('roger_k'),
  rogerDual('roger_dual'),
  rogerMoto('roger_moto'),
  denyBuzz('deny_buzz'),
  totWarn('tot_warn'),
  totCut('tot_cut'),
  linkLost('link_lost'),
  linkUp('link_up'),
  emgAlert('emg_alert'),
  rchkOk('rchk_ok'),
  keyClick('key_click'),
  knobTick('knob_tick'),
  sliderThunk('slider_thunk'),
  powerOn('power_on'),
  powerOff('power_off');

  const SfxId(this.assetStem);

  /// Filename stem under `assets/sfx/v1/` (no extension).
  final String assetStem;

  bool get isLoopBed =>
      this == SfxId.staticBed1 ||
      this == SfxId.staticBed2 ||
      this == SfxId.staticBed3;

  /// Mechanical / scan ticks — voice must not duck for these (TS §7.2).
  bool get isCosmetic =>
      this == SfxId.keyClick ||
      this == SfxId.knobTick ||
      this == SfxId.sliderThunk ||
      this == SfxId.scanTick;

  /// One-shot programme SFX ducks voice; beds and cosmetics do not.
  bool get ducksVoice => !isLoopBed && !isCosmetic;

  bool get isEmergency => this == SfxId.emgAlert;
}
