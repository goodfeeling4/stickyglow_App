import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/utils/ssh_key_helper.dart';

void main() {
  group('SshSyncService ssh-copy-id script tests', () {
    test('buildInstallKeyScript generates valid, secure, idempotent shell command', () {
      const sampleKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey stickyapp@android';
      final base64Key = base64.encode(utf8.encode(sampleKey));

      final script = SshSyncService.buildInstallKeyScript(base64Key);

      // Verify strict permissions
      expect(script, contains('umask 077'));
      expect(script, contains('mkdir -p ~/.ssh'));
      expect(script, contains('chmod 700 ~/.ssh'));
      expect(script, contains('touch ~/.ssh/authorized_keys'));
      expect(script, contains('chmod 600 ~/.ssh/authorized_keys'));

      // Verify base64 decode and grep idempotence
      expect(script, contains('echo "$base64Key" | base64 -d'));
      expect(script, contains('grep -q -F "\$K" ~/.ssh/authorized_keys'));
      expect(script, contains('printf "%s\\n" "\$K" >> ~/.ssh/authorized_keys'));
    });

    test('base64 encoding of generated Ed25519 key roundtrips cleanly', () {
      final keypair = SshKeyHelper.generateEd25519KeyPair(comment: 'unit-test');
      final encoded = base64.encode(utf8.encode(keypair.publicKeyOpenSsh));
      final decoded = utf8.decode(base64.decode(encoded));

      expect(decoded, equals(keypair.publicKeyOpenSsh));
      expect(decoded, startsWith('ssh-ed25519 '));
      expect(decoded, endsWith(' unit-test'));
    });

    test('installPublicKeyViaPassword throws when host cannot be reached via TCP', () async {
      final service = SshSyncService();
      final keypair = SshKeyHelper.generateEd25519KeyPair();

      // Test with non-routable address / unused port that fails immediately
      expect(
        () => service.installPublicKeyViaPassword(
          host: '127.0.0.1',
          port: 59999, // Unused port
          username: 'nobody',
          password: 'fakepassword',
          publicKeyOpenSsh: keypair.publicKeyOpenSsh,
          privateKeyPem: keypair.privateKeyPem,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
