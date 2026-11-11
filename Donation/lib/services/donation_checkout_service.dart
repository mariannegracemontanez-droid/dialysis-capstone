import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The three donation modes, as stored in `donations.allocation_type`.
enum DonationMode {
  specificCenter('specific_center'),
  randomCenter('random_center'),
  allCenters('equal_distribution');

  const DonationMode(this.value);
  final String value;

  static DonationMode? fromValue(String? value) {
    for (final mode in values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}

/// Server-side payment settings (`donation_payment_settings`).
class DonationPaymentSettings {
  const DonationPaymentSettings({
    required this.environment,
    required this.simulatorEnabled,
    required this.paymongoTestEnabled,
    required this.minAmountCentavos,
    required this.maxAmountCentavos,
  });

  /// Used until the settings row has loaded; matches the migration defaults.
  static const fallback = DonationPaymentSettings(
    environment: 'sandbox',
    simulatorEnabled: true,
    paymongoTestEnabled: false,
    minAmountCentavos: 2000,
    maxAmountCentavos: 10000000,
  );

  final String environment;
  final bool simulatorEnabled;
  final bool paymongoTestEnabled;
  final int minAmountCentavos;
  final int maxAmountCentavos;

  bool get isSandbox => environment == 'sandbox';

  factory DonationPaymentSettings.fromJson(Map<String, dynamic> json) {
    return DonationPaymentSettings(
      environment: json['environment']?.toString() ?? 'sandbox',
      simulatorEnabled: json['simulator_enabled'] == true,
      paymongoTestEnabled: json['paymongo_test_enabled'] == true,
      minAmountCentavos: _asInt(json['min_amount_centavos']) ?? 2000,
      maxAmountCentavos: _asInt(json['max_amount_centavos']) ?? 10000000,
    );
  }
}

class CheckoutAllocation {
  const CheckoutAllocation({
    required this.clinicId,
    required this.clinicName,
    required this.amountCentavos,
    required this.status,
  });

  final String clinicId;
  final String clinicName;
  final int amountCentavos;
  final String? status;

  factory CheckoutAllocation.fromJson(Map<String, dynamic> json) {
    return CheckoutAllocation(
      clinicId: json['clinic_id']?.toString() ?? '',
      clinicName: json['clinic_name']?.toString() ?? 'Unnamed Center',
      amountCentavos: _asInt(json['amount_centavos']) ?? 0,
      status: json['allocation_status']?.toString(),
    );
  }
}

/// A donation as the server recorded it. Everything here -- including the
/// recipient(s) -- comes back from the database, never from local state.
class DonationCheckout {
  const DonationCheckout({
    required this.donationId,
    required this.reference,
    required this.mode,
    required this.amountCentavos,
    required this.paymentProvider,
    required this.paymentEnvironment,
    required this.paymentStatus,
    required this.allocations,
    this.statusReason,
    this.checkoutUrl,
    this.confirmedAt,
    this.createdAt,
  });

  final String donationId;
  final String reference;
  final DonationMode? mode;
  final int amountCentavos;
  final String paymentProvider;
  final String paymentEnvironment;
  final String paymentStatus;
  final String? statusReason;
  final String? checkoutUrl;
  final List<CheckoutAllocation> allocations;

  /// When the server recorded the payment result (`payment_confirmed_at`).
  final DateTime? confirmedAt;

  /// When the donation was created (`created_at`).
  final DateTime? createdAt;

  bool get isSandbox => paymentEnvironment == 'sandbox';
  bool get usesSimulator => paymentProvider == 'internal_simulator';
  bool get usesPaymongo => paymentProvider == 'paymongo';
  bool get isOpen => paymentStatus == 'pending' || paymentStatus == 'processing';
  bool get isSuccessful =>
      paymentStatus == 'paid' || paymentStatus == 'simulated_paid';

  factory DonationCheckout.fromJson(Map<String, dynamic> json) {
    final allocations = json['allocations'];
    return DonationCheckout(
      donationId: json['donation_id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      mode: DonationMode.fromValue(json['mode']?.toString()),
      amountCentavos: _asInt(json['amount_centavos']) ?? 0,
      paymentProvider: json['payment_provider']?.toString() ?? '',
      paymentEnvironment: json['payment_environment']?.toString() ?? '',
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      statusReason: json['status_reason']?.toString(),
      checkoutUrl: json['checkout_url']?.toString(),
      confirmedAt: DateTime.tryParse(json['payment_confirmed_at']?.toString() ?? '')?.toLocal(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      allocations: allocations is List
          ? [
              for (final item in allocations)
                CheckoutAllocation.fromJson(Map<String, dynamic>.from(item as Map)),
            ]
          : const [],
    );
  }
}

/// A failure the donor can act on, with a message safe to show them.
class DonationCheckoutException implements Exception {
  const DonationCheckoutException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

// ------------------------------------------------------------------ math

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

/// Parses the amount field into integer centavos: plain digits with at most
/// two decimal places. Never goes through floating point, so "0.29" is
/// exactly 29 centavos. Returns null for anything else.
int? parseAmountToCentavos(String input) {
  final value = input.trim();
  final match = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(value);
  if (match == null) return null;

  final whole = match.group(1) ?? '';
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  // Keeps the result well inside a 64-bit int / JS-safe integer.
  if (whole.length > 12) return null;

  final pesos = whole.isEmpty ? 0 : int.parse(whole);
  final centavos = fraction.isEmpty ? 0 : int.parse(fraction.padRight(2, '0'));
  return pesos * 100 + centavos;
}

/// Splits [totalCentavos] into [count] integer shares that sum exactly to
/// the total. The first `total % count` shares get one extra centavo.
///
/// This is only the donor-side PREVIEW. The authoritative split is made by
/// `donation_equal_split()` in the database with the same rule and the same
/// centre order (name, then id).
List<int> splitCentavosEqually(int totalCentavos, int count) {
  if (count <= 0 || totalCentavos <= 0 || totalCentavos < count) return const [];

  final base = totalCentavos ~/ count;
  final remainder = totalCentavos % count;
  return List<int>.generate(count, (i) => base + (i < remainder ? 1 : 0));
}

/// "₱1,234.56" from integer centavos.
String formatCentavos(int centavos) {
  final negative = centavos < 0;
  final abs = centavos.abs();
  final pesos = (abs ~/ 100).toString();
  final cents = (abs % 100).toString().padLeft(2, '0');

  final grouped = StringBuffer();
  for (int i = 0; i < pesos.length; i++) {
    if (i > 0 && (pesos.length - i) % 3 == 0) grouped.write(',');
    grouped.write(pesos[i]);
  }
  return '${negative ? '-' : ''}₱$grouped.$cents';
}

/// The amount field's text for [centavos]: "250" for 25000, "1000.01" for
/// 100001 -- exactly what [parseAmountToCentavos] reads back.
String centavosToAmountInput(int centavos) {
  if (centavos <= 0) return '';
  final pesos = centavos ~/ 100;
  final cents = centavos % 100;
  return cents == 0 ? '$pesos' : '$pesos.${cents.toString().padLeft(2, '0')}';
}

/// Sorts centres the same way the server does before splitting.
List<Map<String, dynamic>> sortCentersForAllocation(
  List<Map<String, dynamic>> centers,
) {
  final sorted = List<Map<String, dynamic>>.from(centers);
  sorted.sort((a, b) {
    final byName = (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    if (byName != 0) return byName;
    return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
  });
  return sorted;
}

String _randomToken(int bytes) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

/// The only host PayMongo checkout pages are served from.
const String kPaymongoCheckoutHost = 'checkout.paymongo.com';

/// Returns [raw] as a [Uri] only when it is an https URL on exactly
/// `checkout.paymongo.com` (no other subdomain), with no user info and no
/// non-default port. Anything else -- including null, relative, malformed or
/// whitespace-padded input -- returns null. Mirrors `validateCheckoutUrl` in
/// supabase/functions/_shared/paymongo.ts.
Uri? trustedPaymongoCheckoutUri(String? raw) {
  if (raw == null || raw.isEmpty || raw.length > 2048) return null;
  if (RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(raw)) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'https') return null;
  if (uri.host.toLowerCase() != kPaymongoCheckoutHost) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (uri.hasPort && uri.port != 443) return null;
  return uri;
}

/// Validates the `paymongo-create-checkout` response for [donationId]: it
/// must be a checkout object for that same donation, and any checkout URL in
/// it must be a genuine PayMongo checkout URL. Throws otherwise.
DonationCheckout parsePaymongoCheckoutResponse(Object? data, String donationId) {
  if (data is! Map) throw const FormatException('not a checkout object');
  final checkout = DonationCheckout.fromJson(Map<String, dynamic>.from(data));
  if (checkout.donationId.isEmpty || checkout.donationId != donationId) {
    throw const FormatException('checkout is for a different donation');
  }
  if (checkout.checkoutUrl != null &&
      trustedPaymongoCheckoutUri(checkout.checkoutUrl) == null) {
    throw const FormatException('untrusted checkout URL');
  }
  return checkout;
}

/// Turns a database error ("CODE: message") into a donor-safe message.
DonationCheckoutException mapCheckoutError(Object error) {
  final raw = error is PostgrestException ? error.message : error.toString();
  final match = RegExp(r'([A-Z_]{4,}):\s*(.*)').firstMatch(raw);
  final code = match?.group(1) ?? 'UNKNOWN';

  const messages = {
    'NO_ELIGIBLE_CENTERS':
        'No dialysis centers are currently accepting donations. Please try again later.',
    'CENTER_NOT_ELIGIBLE':
        'The selected center is no longer accepting donations. Please choose another center.',
    'INVALID_AMOUNT': 'Please enter an amount within the allowed range.',
    'AMOUNT_TOO_SMALL_TO_SPLIT':
        'The amount is too small to divide among all centers.',
    'LOGIN_REQUIRED': 'Please log in to your donor account before continuing.',
    'PAYMENTS_UNAVAILABLE': 'Online donations are not available right now.',
    'SIMULATOR_DISABLED': 'The demo payment simulator is not enabled.',
    'ALREADY_FINALIZED': 'This donation has already been completed or closed.',
    'DONATION_NOT_FOUND': 'This donation could not be found.',
  };

  return DonationCheckoutException(
    code,
    messages[code] ??
        'Something went wrong while processing your donation. Please try again.',
  );
}

// --------------------------------------------------------------- service

/// The one place the Donation app talks to the payment workflow. All writes
/// go through SECURITY DEFINER database functions; the app never inserts
/// donations or allocations itself.
class DonationCheckoutService {
  DonationCheckoutService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _pendingKey = 'curenurture.pending_checkout';

  Future<DonationPaymentSettings> fetchSettings() async {
    final row = await _client
        .from('donation_payment_settings')
        .select()
        .maybeSingle();
    return row == null
        ? DonationPaymentSettings.fallback
        : DonationPaymentSettings.fromJson(row);
  }

  /// Centres that may receive donations, in the server's allocation order.
  Future<List<Map<String, dynamic>>> fetchEligibleCenters() async {
    final rows = await _client.rpc('donation_eligible_centers');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Starts a donation. [request] carries the idempotency key and secret, so
  /// retrying the same request returns the same donation.
  Future<DonationCheckout> createCheckout(CheckoutRequest request) async {
    try {
      final result = await _client.rpc('create_donation_checkout', params: {
        'p_mode': request.mode.value,
        'p_amount_centavos': request.amountCentavos,
        'p_clinic_id':
            request.mode == DonationMode.specificCenter ? request.clinicId : null,
        'p_idempotency_key': request.idempotencyKey,
        'p_client_secret': request.clientSecret,
        'p_anonymous': request.anonymous,
        'p_donor_name': request.donorName,
      });
      final checkout =
          DonationCheckout.fromJson(Map<String, dynamic>.from(result as Map));
      // The request is remembered with the checkout so Back, a refresh or a
      // retry replays the SAME keys: the server then returns this donation
      // (same random centre, same split) instead of creating a new one.
      // It is bound to who started it, so on a shared browser another
      // account is never offered it.
      await savePending(
        checkout.donationId,
        request.clientSecret,
        request: request,
        owner: request.anonymous ? kAnonymousPendingOwner : _client.auth.currentUser?.id,
      );
      return checkout;
    } catch (e) {
      throw mapCheckoutError(e);
    }
  }

  Future<DonationCheckout> fetchCheckout(String donationId, String secret) =>
      _call('get_donation_checkout', {
        'p_donation_id': donationId,
        'p_client_secret': secret,
      });

  Future<DonationCheckout> cancel(String donationId, String secret) =>
      _call('cancel_donation_checkout', {
        'p_donation_id': donationId,
        'p_client_secret': secret,
      });

  /// Demo simulator: [outcome] is 'success', 'failure' or 'cancel'.
  Future<DonationCheckout> simulate(
    String donationId,
    String secret,
    String outcome,
  ) =>
      _call('simulate_donation_payment', {
        'p_donation_id': donationId,
        'p_client_secret': secret,
        'p_outcome': outcome,
      });

  /// Asks the `paymongo-create-checkout` Edge Function for a PayMongo TEST
  /// checkout URL. The PayMongo secret key lives only in that function.
  Future<DonationCheckout> startPaymongoCheckout(
    String donationId,
    String secret,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'paymongo-create-checkout',
        body: {'donation_id': donationId, 'client_secret': secret},
      );
      // Malformed, mismatched or untrusted responses fail closed below.
      return parsePaymongoCheckoutResponse(response.data, donationId);
    } catch (e) {
      throw const DonationCheckoutException(
        'PAYMONGO_UNAVAILABLE',
        'The PayMongo test checkout could not be opened. Please try again.',
      );
    }
  }

  Future<DonationCheckout> _call(String fn, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc(fn, params: params);
      return DonationCheckout.fromJson(Map<String, dynamic>.from(result as Map));
    } catch (e) {
      throw mapCheckoutError(e);
    }
  }

  // A pending checkout is remembered in this browser so a refresh (or a
  // trip to the PayMongo page) can resume it with the SAME recipients.

  Future<void> savePending(
    String donationId,
    String secret, {
    CheckoutRequest? request,
    String? owner,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingKey,
        encodePendingCheckout(donationId, secret, request: request, owner: owner),
      );
    } catch (_) {
      // Storage unavailable (private window): the checkout still works, it
      // just cannot be resumed after a refresh.
    }
  }

  Future<PendingCheckout?> loadPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return null;
      final pending = decodePendingCheckout(raw);
      // Entries saved by an earlier version may still hold the donor's name:
      // rewrite them without it (the resume data itself is unchanged).
      if (pending != null && pendingCheckoutStoresDonorName(raw)) {
        await prefs.setString(
          _pendingKey,
          encodePendingCheckout(pending.id, pending.secret,
              request: pending.request, owner: pending.owner),
        );
      }
      return pending;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (_) {}
  }
}

/// One donation attempt. Created once per submit and reused on retry, so a
/// double click or a network retry cannot create a second donation.
class CheckoutRequest {
  CheckoutRequest({
    required this.mode,
    required this.amountCentavos,
    required this.anonymous,
    this.clinicId,
    this.donorName,
  })  : idempotencyKey = _randomToken(24),
        clientSecret = _randomToken(32),
        donorNameUnknown = false;

  /// A request read back from browser storage. The donor's name is never
  /// stored there, so it is unknown here ([donorNameUnknown]); the donation
  /// it identifies already exists on the server with the original name.
  CheckoutRequest._restored({
    required this.mode,
    required this.amountCentavos,
    required this.anonymous,
    required this.idempotencyKey,
    required this.clientSecret,
    this.clinicId,
  })  : donorName = null,
        donorNameUnknown = true;

  final DonationMode mode;
  final int amountCentavos;
  final bool anonymous;
  final String? clinicId;
  final String? donorName;
  final String idempotencyKey;
  final String clientSecret;

  /// True for a request restored from browser storage (no name kept there).
  final bool donorNameUnknown;

  /// True when [other] would create the same donation (so the same keys may
  /// be reused for a retry). For a restored request the name cannot be
  /// compared and is ignored: replaying its keys returns the existing
  /// donation, which keeps the name it was created with.
  bool sameAs({
    required DonationMode mode,
    required int amountCentavos,
    required String? clinicId,
    required bool anonymous,
    required String? donorName,
  }) =>
      this.mode == mode &&
      this.amountCentavos == amountCentavos &&
      this.clinicId == clinicId &&
      this.anonymous == anonymous &&
      (donorNameUnknown || this.donorName == donorName);
}

/// A checkout remembered in this browser: enough to reload it from the
/// server and, when [request] is present, to replay the original request.
/// [owner] is who started it: [kAnonymousPendingOwner] for an anonymous
/// donation, otherwise the Auth user id (null when unknown).
typedef PendingCheckout = ({
  String id,
  String secret,
  CheckoutRequest? request,
  String? owner,
});

/// Owner marker for an unfinished ANONYMOUS donation in this browser.
const String kAnonymousPendingOwner = 'anonymous';

/// Whether [pending] may be offered in the current flow: the anonymous
/// donation flow only gets anonymous donations; a signed-in donor only gets
/// donations they started while signed in. Anything else (another account,
/// unknown owner) is never offered.
bool pendingBelongsTo(
  PendingCheckout pending, {
  required bool anonymousFlow,
  String? userId,
}) {
  if (anonymousFlow) return pending.owner == kAnonymousPendingOwner;
  return userId != null && userId.isNotEmpty && pending.owner == userId;
}

/// Serialises the pending checkout. The client secret is stored once (as
/// `secret`); the request part holds only what is needed to resend it.
/// The donor's name is deliberately NOT stored in the browser: it is kept
/// only on the server-side donation record.
String encodePendingCheckout(
  String donationId,
  String secret, {
  CheckoutRequest? request,
  String? owner,
}) {
  return jsonEncode({
    'id': donationId,
    'secret': secret,
    if (owner != null && owner.isNotEmpty) 'owner': owner,
    if (request != null && request.clientSecret == secret)
      'request': {
        'mode': request.mode.value,
        'amount_centavos': request.amountCentavos,
        'clinic_id': request.clinicId,
        'anonymous': request.anonymous,
        'idempotency_key': request.idempotencyKey,
      },
  });
}

/// True when [raw] still carries a `donor_name` (written by an earlier
/// version); [DonationCheckoutService.loadPending] then rewrites it without.
bool pendingCheckoutStoresDonorName(String raw) {
  try {
    final data = jsonDecode(raw);
    return data is Map && data['request'] is Map && (data['request'] as Map).containsKey('donor_name');
  } catch (_) {
    return false;
  }
}

/// Reads what [encodePendingCheckout] wrote. Also accepts the older
/// `{id, secret}` form (no request) and older entries that still contain a
/// `donor_name`, which is ignored. Returns null for anything malformed; a
/// malformed request part only drops the request.
PendingCheckout? decodePendingCheckout(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return null;
    final id = data['id'];
    final secret = data['secret'];
    if (id is! String || id.isEmpty || secret is! String || secret.isEmpty) return null;

    CheckoutRequest? request;
    final r = data['request'];
    if (r is Map) {
      final mode = DonationMode.fromValue(r['mode']?.toString());
      final amount = r['amount_centavos'];
      final key = r['idempotency_key'];
      final anonymous = r['anonymous'];
      final clinicId = r['clinic_id'];
      // Any 'donor_name' (older entries) is ignored, never read back.
      if (mode != null &&
          amount is int &&
          amount > 0 &&
          key is String &&
          key.length >= 16 &&
          anonymous is bool &&
          (clinicId == null || clinicId is String) &&
          (mode == DonationMode.specificCenter) == (clinicId != null)) {
        request = CheckoutRequest._restored(
          mode: mode,
          amountCentavos: amount,
          anonymous: anonymous,
          clinicId: clinicId as String?,
          idempotencyKey: key,
          clientSecret: secret,
        );
      }
    }
    // Older entries have no owner: an anonymous request can only have come
    // from the anonymous flow; anything else stays unknown (never offered).
    final rawOwner = data['owner'];
    final owner = rawOwner is String && rawOwner.isNotEmpty
        ? rawOwner
        : (request?.anonymous == true ? kAnonymousPendingOwner : null);
    return (id: id, secret: secret, request: request, owner: owner);
  } catch (_) {
    return null;
  }
}
