//! CTAPHID framing for the Linux virtual FIDO2 authenticator.
//!
//! Bytes in, bytes out: the browser talks in 64-byte HID reports; this state
//! machine turns them into (command, payload) messages and back. Constants
//! pinned against libfido2's `fido/param.h` (system copy) and CTAP 2.1 §11.2.
//! Pure logic — no device I/O here (that is the uhid transport's job).

const BROADCAST_CID: u32 = 0xffff_ffff;
const FRAME_INIT: u8 = 0x80;
const CMD_PING: u8 = 0x01;
const CMD_INIT: u8 = 0x06;
const CMD_CBOR: u8 = 0x10;
const CMD_KEEPALIVE: u8 = 0x3b;
const CMD_ERROR: u8 = 0x3f;
/// KEEPALIVE status: the authenticator is still processing (waiting on the user).
const KEEPALIVE_PROCESSING: u8 = 0x01;
const ERR_INVALID_COMMAND: u8 = 0x01;
const ERR_INVALID_SEQ: u8 = 0x04;
const ERR_CHANNEL_BUSY: u8 = 0x06;
const ERR_INVALID_CHANNEL: u8 = 0x0b;
const CAP_CBOR: u8 = 0x04;
const CAP_NMSG: u8 = 0x08;
const PROTOCOL_VERSION: u8 = 2;
const INIT_PAYLOAD_LEN: u16 = 17;

/// An inbound message still collecting continuation packets.
struct Pending {
    cid: u32,
    cmd: u8,
    total: usize,
    buf: Vec<u8>,
    next_seq: u8,
}

/// CTAPHID framing state machine: one per virtual device.
pub struct Ctaphid {
    /// Next channel id to hand out; 0 and 0xffffffff are reserved.
    next_cid: u32,
    pending: Option<Pending>,
    complete: Option<(u32, u8, Vec<u8>)>,
}

impl Default for Ctaphid {
    fn default() -> Self {
        Self {
            next_cid: 1,
            pending: None,
            complete: None,
        }
    }
}

impl Ctaphid {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed one 64-byte host-to-device report; returns the device-to-host
    /// reports ready to send (empty while a multi-packet message is pending).
    pub fn handle_report(&mut self, report: &[u8; 64]) -> Vec<[u8; 64]> {
        let cid = u32::from_be_bytes([report[0], report[1], report[2], report[3]]);
        if cid == BROADCAST_CID && report[4] == FRAME_INIT | CMD_INIT {
            return vec![self.init_response(report)];
        }
        if report[4] & FRAME_INIT != 0 {
            // Init packet: starts a message; short ones complete immediately.
            if !self.allocated(cid) {
                return encode_message(cid, CMD_ERROR, &[ERR_INVALID_CHANNEL]);
            }
            if self.pending.is_some() {
                return encode_message(cid, CMD_ERROR, &[ERR_CHANNEL_BUSY]);
            }
            let cmd = report[4] & !FRAME_INIT;
            let total = u16::from_be_bytes([report[5], report[6]]) as usize;
            let take = total.min(57);
            let buf = report[7..7 + take].to_vec();
            if buf.len() == total {
                return self.finish(cid, cmd, buf);
            } else {
                self.pending = Some(Pending {
                    cid,
                    cmd,
                    total,
                    buf,
                    next_seq: 0,
                });
            }
        } else if let Some(p) = self.pending.as_mut() {
            // Continuation packets for the pending message; strays (other
            // channels, or nothing pending) are ignored per spec.
            if p.cid == cid {
                if report[4] != p.next_seq {
                    self.pending = None; // message aborted
                    return encode_message(cid, CMD_ERROR, &[ERR_INVALID_SEQ]);
                }
                let take = (p.total - p.buf.len()).min(59);
                p.buf.extend_from_slice(&report[5..5 + take]);
                p.next_seq += 1;
                if p.buf.len() == p.total {
                    let done = self.pending.take().expect("pending was just Some");
                    return self.finish(done.cid, done.cmd, done.buf);
                }
            }
        }
        Vec::new()
    }

    /// True when `cid` has been handed out by our INIT handler.
    fn allocated(&self, cid: u32) -> bool {
        cid >= 1 && cid < self.next_cid
    }

    /// A message is fully reassembled: transport-level commands (PING) are
    /// answered here; everything else is queued for the daemon loop.
    fn finish(&mut self, cid: u32, cmd: u8, buf: Vec<u8>) -> Vec<[u8; 64]> {
        match cmd {
            CMD_PING => encode_message(cid, CMD_PING, &buf),
            CMD_CBOR => {
                self.complete = Some((cid, cmd, buf));
                Vec::new()
            }
            // Everything else — including MSG (U2F), which NMSG disclaims —
            // gets the standard refusal instead of a browser-hanging silence.
            _ => encode_message(cid, CMD_ERROR, &[ERR_INVALID_COMMAND]),
        }
    }

    /// INIT response on the broadcast channel: echo the nonce, allocate a CID.
    fn init_response(&mut self, report: &[u8; 64]) -> [u8; 64] {
        let cid = self.next_cid;
        self.next_cid += 1;
        let mut r = [0u8; 64];
        r[0..4].copy_from_slice(&BROADCAST_CID.to_be_bytes());
        r[4] = FRAME_INIT | CMD_INIT;
        r[5..7].copy_from_slice(&INIT_PAYLOAD_LEN.to_be_bytes());
        r[7..15].copy_from_slice(&report[7..15]); // nonce, echoed verbatim
        r[15..19].copy_from_slice(&cid.to_be_bytes());
        r[19] = PROTOCOL_VERSION;
        // r[20..23]: device version major/minor/build — zeros, like the AAGUID.
        r[23] = CAP_CBOR | CAP_NMSG;
        r
    }

    /// The next fully reassembled inbound message, if one is complete:
    /// (channel id, command, payload). The daemon loop polls this after every
    /// `handle_report` and routes the message to the CTAP2 layer.
    pub fn take_message(&mut self) -> Option<(u32, u8, Vec<u8>)> {
        self.complete.take()
    }
}

/// A single CTAPHID_KEEPALIVE packet on `cid` with status "processing" (0x01):
/// sent every ~100ms while a request waits on the user, so the browser does
/// not time the operation out mid-consent.
pub fn keepalive_processing(cid: u32) -> [u8; 64] {
    encode_message(cid, CMD_KEEPALIVE, &[KEEPALIVE_PROCESSING])[0]
}

/// Encode one outbound message as 64-byte reports: an init packet
/// (CID | cmd|0x80 | BCNT | 57 data bytes) and, for longer payloads,
/// seq-numbered continuation packets.
pub fn encode_message(cid: u32, cmd: u8, payload: &[u8]) -> Vec<[u8; 64]> {
    let mut r = [0u8; 64];
    r[0..4].copy_from_slice(&cid.to_be_bytes());
    r[4] = FRAME_INIT | cmd;
    r[5..7].copy_from_slice(&(payload.len() as u16).to_be_bytes());
    let n = payload.len().min(57);
    r[7..7 + n].copy_from_slice(&payload[..n]);
    let mut reports = vec![r];
    for (seq, chunk) in payload[n..].chunks(59).enumerate() {
        let mut c = [0u8; 64];
        c[0..4].copy_from_slice(&cid.to_be_bytes());
        c[4] = seq as u8; // continuation: high bit clear, 0x00..=0x7f
        c[5..5 + chunk.len()].copy_from_slice(chunk);
        reports.push(c);
    }
    reports
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build an init packet: CID | cmd|0x80 | BCNT(total) | data.
    fn init_packet(cid: u32, cmd: u8, total: u16, data: &[u8]) -> [u8; 64] {
        let mut p = [0u8; 64];
        p[0..4].copy_from_slice(&cid.to_be_bytes());
        p[4] = 0x80 | cmd;
        p[5..7].copy_from_slice(&total.to_be_bytes());
        p[7..7 + data.len()].copy_from_slice(data);
        p
    }

    /// Build a continuation packet: CID | seq | data.
    fn cont_packet(cid: u32, seq: u8, data: &[u8]) -> [u8; 64] {
        let mut p = [0u8; 64];
        p[0..4].copy_from_slice(&cid.to_be_bytes());
        p[4] = seq;
        p[5..5 + data.len()].copy_from_slice(data);
        p
    }

    /// Run the INIT dance and return the allocated channel id.
    fn init_channel(hid: &mut Ctaphid) -> u32 {
        let mut req = [0u8; 64];
        req[0..4].copy_from_slice(&0xffff_ffffu32.to_be_bytes());
        req[4] = 0x80 | 0x06;
        req[6] = 8;
        req[7..15].copy_from_slice(b"nonce123");
        let out = hid.handle_report(&req);
        u32::from_be_bytes([out[0][15], out[0][16], out[0][17], out[0][18]])
    }

    #[test]
    fn init_on_broadcast_echoes_nonce_and_allocates_a_channel() {
        // CTAP 2.1 §11.2.9.1.3: INIT on the broadcast channel (0xffffffff)
        // answers on the broadcast channel with a 17-byte payload:
        // nonce(8) | new CID(4) | protocol(1) | major(1) | minor(1) |
        // build(1) | capabilities(1).
        let mut hid = Ctaphid::new();
        let mut req = [0u8; 64];
        req[0..4].copy_from_slice(&0xffff_ffffu32.to_be_bytes());
        req[4] = 0x80 | 0x06; // frame-init bit | CTAPHID_INIT
        req[5] = 0;
        req[6] = 8; // BCNT: an 8-byte nonce
        req[7..15].copy_from_slice(b"nonce123");

        let out = hid.handle_report(&req);

        assert_eq!(out.len(), 1, "INIT answers with exactly one report");
        let r = out[0];
        assert_eq!(&r[0..4], &0xffff_ffffu32.to_be_bytes(), "broadcast CID");
        assert_eq!(r[4], 0x80 | 0x06, "INIT command echoed");
        assert_eq!(u16::from_be_bytes([r[5], r[6]]), 17, "payload length");
        assert_eq!(&r[7..15], b"nonce123", "nonce echoed verbatim");
        let cid = u32::from_be_bytes([r[15], r[16], r[17], r[18]]);
        assert_ne!(cid, 0xffff_ffff, "allocated CID is not broadcast");
        assert_ne!(cid, 0, "allocated CID is not reserved zero");
        assert_eq!(r[19], 2, "CTAPHID protocol version");
        assert_eq!(&r[20..23], &[0, 0, 0], "device version major/minor/build");
        // Capabilities: CBOR (0x04) set, NMSG (0x08) set — no U2F. WINK unset.
        assert_eq!(r[23], 0x04 | 0x08);
    }

    #[test]
    fn short_reply_fits_one_packet_with_correct_byte_count() {
        // 57 bytes is the init-packet maximum: 64 - CID(4) - cmd(1) - BCNT(2).
        let full = encode_message(0x0102_0304, 0x10, &[0xAA; 57]);
        assert_eq!(full.len(), 1, "57 bytes still fits one packet");
        let r = full[0];
        assert_eq!(&r[0..4], &[1, 2, 3, 4], "CID");
        assert_eq!(r[4], 0x80 | 0x10, "frame-init bit | command");
        assert_eq!(u16::from_be_bytes([r[5], r[6]]), 57, "BCNT");
        assert_eq!(&r[7..64], &[0xAA; 57]);

        // A shorter payload declares its true length and zero-pads the rest.
        let short = encode_message(0x0102_0304, 0x10, &[0xBB, 0xCC]);
        assert_eq!(short.len(), 1);
        let r = short[0];
        assert_eq!(u16::from_be_bytes([r[5], r[6]]), 2, "BCNT is payload size");
        assert_eq!(&r[7..9], &[0xBB, 0xCC]);
        assert_eq!(&r[9..64], &[0u8; 55], "zero padding after the payload");
    }

    #[test]
    fn long_reply_fragments_into_numbered_continuations_and_round_trips() {
        // Continuation packets: CID(4) | seq(1) | 59 data bytes.
        // 200 bytes = init 57 + continuations 59 + 59 + 25.
        let payload: Vec<u8> = (0..200u16).map(|i| i as u8).collect();
        let reports = encode_message(0x0102_0304, 0x10, &payload);
        assert_eq!(reports.len(), 4);
        for r in &reports {
            assert_eq!(&r[0..4], &[1, 2, 3, 4], "same CID on every packet");
        }
        assert_eq!(u16::from_be_bytes([reports[0][5], reports[0][6]]), 200);
        assert_eq!(reports[1][4], 0, "continuation seq starts at 0");
        assert_eq!(reports[2][4], 1);
        assert_eq!(reports[3][4], 2);

        // Reassemble exactly as a browser would and compare byte-for-byte.
        let mut got = reports[0][7..64].to_vec();
        for r in &reports[1..] {
            got.extend_from_slice(&r[5..64]);
        }
        got.truncate(200);
        assert_eq!(got, payload);
    }

    #[test]
    fn multi_packet_request_reassembles() {
        let mut hid = Ctaphid::new();
        let cid = init_channel(&mut hid);
        // A 100-byte CBOR request: init packet carries 57, continuation 43.
        let payload: Vec<u8> = (0..100u16).map(|i| (i ^ 0x5a) as u8).collect();

        let mut p0 = [0u8; 64];
        p0[0..4].copy_from_slice(&cid.to_be_bytes());
        p0[4] = 0x80 | 0x10; // CTAPHID_CBOR
        p0[5..7].copy_from_slice(&100u16.to_be_bytes());
        p0[7..64].copy_from_slice(&payload[..57]);
        assert!(hid.handle_report(&p0).is_empty(), "no reply mid-message");
        assert!(hid.take_message().is_none(), "message not complete yet");

        let mut p1 = [0u8; 64];
        p1[0..4].copy_from_slice(&cid.to_be_bytes());
        p1[4] = 0; // continuation seq 0
        p1[5..48].copy_from_slice(&payload[57..]);
        assert!(hid.handle_report(&p1).is_empty());

        let (mcid, cmd, body) = hid.take_message().expect("message complete");
        assert_eq!(mcid, cid);
        assert_eq!(cmd, 0x10);
        assert_eq!(body, payload, "reassembled byte-for-byte");
        assert!(hid.take_message().is_none(), "delivered exactly once");
    }

    #[test]
    fn ping_echoes_its_payload_verbatim() {
        let mut hid = Ctaphid::new();
        let cid = init_channel(&mut hid);
        let mut p = [0u8; 64];
        p[0..4].copy_from_slice(&cid.to_be_bytes());
        p[4] = 0x80 | 0x01; // CTAPHID_PING
        p[5..7].copy_from_slice(&4u16.to_be_bytes());
        p[7..11].copy_from_slice(b"echo");

        let out = hid.handle_report(&p);

        assert_eq!(out.len(), 1, "PING answers immediately");
        assert_eq!(&out[0][0..4], &cid.to_be_bytes(), "same channel");
        assert_eq!(out[0][4], 0x80 | 0x01, "PING command echoed");
        assert_eq!(u16::from_be_bytes([out[0][5], out[0][6]]), 4);
        assert_eq!(&out[0][7..11], b"echo");
        assert!(
            hid.take_message().is_none(),
            "transport handles PING; the daemon never sees it"
        );
    }

    #[test]
    fn unknown_command_gets_error_invalid_command() {
        let mut hid = Ctaphid::new();
        let cid = init_channel(&mut hid);
        let mut p = [0u8; 64];
        p[0..4].copy_from_slice(&cid.to_be_bytes());
        p[4] = 0x80 | 0x2a; // no such CTAPHID command
                            // BCNT 0: nothing else needed to judge the command byte.

        let out = hid.handle_report(&p);

        assert_eq!(out.len(), 1, "refusal, not silence");
        assert_eq!(&out[0][0..4], &cid.to_be_bytes(), "same channel");
        assert_eq!(out[0][4], 0x80 | 0x3f, "CTAPHID_ERROR");
        assert_eq!(u16::from_be_bytes([out[0][5], out[0][6]]), 1);
        assert_eq!(out[0][7], 0x01, "ERR_INVALID_COMMAND");
        assert!(hid.take_message().is_none(), "daemon never sees it");
    }

    #[test]
    fn message_on_a_never_allocated_channel_gets_invalid_channel() {
        let mut hid = Ctaphid::new();
        let _cid = init_channel(&mut hid);
        let foreign = 0x9999_9999u32;

        let out = hid.handle_report(&init_packet(foreign, 0x10, 1, &[0x04]));

        assert_eq!(out.len(), 1, "refusal, not silence");
        assert_eq!(&out[0][0..4], &foreign.to_be_bytes());
        assert_eq!(out[0][4], 0x80 | 0x3f, "CTAPHID_ERROR");
        assert_eq!(out[0][7], 0x0b, "ERR_INVALID_CHANNEL");
        assert!(hid.take_message().is_none());
    }

    #[test]
    fn message_while_another_is_mid_assembly_gets_channel_busy() {
        let mut hid = Ctaphid::new();
        let a = init_channel(&mut hid);
        let b = init_channel(&mut hid);
        assert!(hid
            .handle_report(&init_packet(a, 0x10, 100, &[0xAA; 57]))
            .is_empty());

        let out = hid.handle_report(&init_packet(b, 0x10, 1, &[0x04]));

        assert_eq!(out.len(), 1, "B is told busy");
        assert_eq!(&out[0][0..4], &b.to_be_bytes(), "error addressed to B");
        assert_eq!(out[0][4], 0x80 | 0x3f, "CTAPHID_ERROR");
        assert_eq!(out[0][7], 0x06, "ERR_CHANNEL_BUSY");

        // A's message is undisturbed and still completes.
        assert!(hid
            .handle_report(&cont_packet(a, 0, &[0xAA; 43]))
            .is_empty());
        let (mcid, _, body) = hid.take_message().expect("A completes");
        assert_eq!(mcid, a);
        assert_eq!(body, vec![0xAA; 100]);
    }

    #[test]
    fn wrong_sequence_number_aborts_with_invalid_seq() {
        let mut hid = Ctaphid::new();
        let a = init_channel(&mut hid);
        assert!(hid
            .handle_report(&init_packet(a, 0x10, 100, &[0xAA; 57]))
            .is_empty());

        // Expected seq 0; send 1.
        let out = hid.handle_report(&cont_packet(a, 1, &[0xAA; 43]));

        assert_eq!(out.len(), 1, "refusal, not silence");
        assert_eq!(out[0][4], 0x80 | 0x3f, "CTAPHID_ERROR");
        assert_eq!(out[0][7], 0x04, "ERR_INVALID_SEQ");
        // The message is aborted: the packet that would have finished it
        // now continues nothing.
        assert!(hid
            .handle_report(&cont_packet(a, 0, &[0xAA; 43]))
            .is_empty());
        assert!(hid.take_message().is_none());
    }

    #[test]
    fn stray_continuation_is_ignored_and_the_current_message_survives() {
        // Born green: the current code already ignores strays. Pinned here
        // because the spec demands silence — an error reply would let any
        // same-user process disrupt a live browser exchange.
        let mut hid = Ctaphid::new();
        let a = init_channel(&mut hid);
        let b = init_channel(&mut hid);
        assert!(hid
            .handle_report(&init_packet(a, 0x10, 100, &[0xAA; 57]))
            .is_empty());

        // Stray: continuation on B, which has no message in progress.
        let out = hid.handle_report(&cont_packet(b, 0, &[0xBB; 43]));
        assert!(out.is_empty(), "ignored, no reply");

        // A still completes cleanly.
        assert!(hid
            .handle_report(&cont_packet(a, 0, &[0xAA; 43]))
            .is_empty());
        let (mcid, _, body) = hid.take_message().expect("A completes");
        assert_eq!(mcid, a);
        assert_eq!(body, vec![0xAA; 100]);
    }

    #[test]
    fn u2f_msg_is_refused_as_advertised_by_nmsg() {
        // Born green: finish() already refuses every non-CBOR command. Pinned
        // separately because the NMSG capability bit in our INIT response
        // promises exactly this; breaking it would strand old-protocol
        // callers in silence.
        let mut hid = Ctaphid::new();
        let cid = init_channel(&mut hid);

        let out = hid.handle_report(&init_packet(cid, 0x03, 4, b"u2f?"));

        assert_eq!(out.len(), 1);
        assert_eq!(out[0][4], 0x80 | 0x3f, "CTAPHID_ERROR");
        assert_eq!(out[0][7], 0x01, "ERR_INVALID_COMMAND");
        assert!(hid.take_message().is_none());
    }

    #[test]
    fn keepalive_processing_frames_a_single_status_packet() {
        let k = keepalive_processing(0x0102_0304);
        assert_eq!(&k[0..4], &[1, 2, 3, 4], "on the request's channel");
        assert_eq!(k[4], 0x80 | 0x3b, "CTAPHID_KEEPALIVE");
        assert_eq!(u16::from_be_bytes([k[5], k[6]]), 1, "one status byte");
        assert_eq!(k[7], 0x01, "status: processing (waiting on the user)");
    }
}
