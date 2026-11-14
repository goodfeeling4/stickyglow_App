import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/utils/ssh_key_helper.dart';

void main() {
  group('SshKeyHelper', () {
    test('generates valid Ed25519 keypair in OpenSSH format', () {
      final keypair = SshKeyHelper.generateEd25519KeyPair(comment: 'test-device@sticky');

      expect(keypair.privateKeyPem, contains('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(keypair.privateKeyPem, contains('-----END OPENSSH PRIVATE KEY-----'));

      expect(keypair.publicKeyOpenSsh, startsWith('ssh-ed25519 '));
      expect(keypair.publicKeyOpenSsh, endsWith(' test-device@sticky'));

      // Validate that dartssh2 can parse the generated PEM
      final parsed = SSHKeyPair.fromPem(keypair.privateKeyPem);
      expect(parsed, isNotEmpty);
      expect(parsed.first.name, equals('ssh-ed25519'));
    });

    test('extractOpenSshPublicKey matches generated public key', () {
      final keypair = SshKeyHelper.generateEd25519KeyPair(comment: 'my-phone');
      final extracted = SshKeyHelper.extractOpenSshPublicKey(keypair.privateKeyPem, comment: 'my-phone');

      expect(extracted, equals(keypair.publicKeyOpenSsh));
    });

    test('extractOpenSshPublicKey returns null for invalid PEM', () {
      final extracted = SshKeyHelper.extractOpenSshPublicKey('not a real key');
      expect(extracted, isNull);
    });

    test('isValidPrivateKey returns true for generated key and false for invalid', () {
      final keypair = SshKeyHelper.generateEd25519KeyPair();
      expect(SshKeyHelper.isValidPrivateKey(keypair.privateKeyPem), isTrue);
      expect(SshKeyHelper.isValidPrivateKey('invalid pem'), isFalse);
    });
  });
}
