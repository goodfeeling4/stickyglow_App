import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

/// Utility class for generating and extracting SSH key pairs on the Android device.
abstract final class SshKeyHelper {
  /// Generates a brand-new Ed25519 SSH keypair directly on this device.
  ///
  /// Returns a record containing:
  /// - `privateKeyPem`: OpenSSH format private key PEM (stored securely on device).
  /// - `publicKeyOpenSsh`: One-line public key string for `~/.ssh/authorized_keys`.
  static ({String privateKeyPem, String publicKeyOpenSsh}) generateEd25519KeyPair({
    String comment = 'stickyapp@android',
  }) {
    final signingKey = ed25519.SigningKey.generate();
    final verifyKey = signingKey.verifyKey;

    // In pinenacl, signingKey.asTypedList is already 64 bytes (32-byte seed + 32-byte pubkey)
    final privateKeyBytes = signingKey.asTypedList;

    final keypair = OpenSSHEd25519KeyPair(
      verifyKey.asTypedList,
      privateKeyBytes,
      comment,
    );

    final privateKeyPem = keypair.toPem();
    final pubKeyBytes = keypair.toPublicKey().encode();
    final pubKeyBase64 = base64.encode(pubKeyBytes);
    final publicKeyOpenSsh = 'ssh-ed25519 $pubKeyBase64 $comment';

    return (
      privateKeyPem: privateKeyPem,
      publicKeyOpenSsh: publicKeyOpenSsh,
    );
  }

  /// Validates whether [privateKeyPem] can be parsed and can sign data.
  static bool isValidPrivateKey(String privateKeyPem) {
    try {
      final keypairs = SSHKeyPair.fromPem(privateKeyPem);
      if (keypairs.isEmpty) return false;
      final key = keypairs.first;
      key.sign(Uint8List(32));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Extracts the OpenSSH public key line from an existing [privateKeyPem].
  ///
  /// Returns `null` if the PEM is invalid or unsupported.
  static String? extractOpenSshPublicKey(
    String privateKeyPem, {
    String comment = 'stickyapp@android',
  }) {
    try {
      final keypairs = SSHKeyPair.fromPem(privateKeyPem);
      if (keypairs.isEmpty) return null;
      final key = keypairs.first;
      final pubKeyBytes = key.toPublicKey().encode();
      final pubKeyBase64 = base64.encode(pubKeyBytes);
      return '${key.name} $pubKeyBase64 $comment';
    } catch (_) {
      return null;
    }
  }
}
