import 'package:flutter/material.dart';
import '../utils/patient_name.dart';
import '../utils/validators.dart';

/// Builds the decoration for one name field so each screen keeps its own
/// input styling.
typedef NameFieldDecoration =
    InputDecoration Function(String label, IconData icon, String? errorText);

/// State for the First / Middle / Last name inputs and the
/// "I don't have a middle name" checkbox.
///
/// When the checkbox is unchecked the middle name is required like the
/// other two parts; checking it clears and disables the field and the
/// middle name is saved as NULL.
class PatientNameController extends ChangeNotifier {
  final TextEditingController first;
  final TextEditingController middle;
  final TextEditingController last;

  /// The un-separated name of a legacy record, shown as a reference while
  /// the patient re-enters it as separate parts.
  final String legacyFullName;

  bool _noMiddleName;
  String? firstError;
  String? middleError;
  String? lastError;

  PatientNameController({PatientName initial = const PatientName()})
    : first = TextEditingController(text: initial.firstName),
      middle = TextEditingController(text: initial.middleName ?? ''),
      last = TextEditingController(text: initial.lastName),
      legacyFullName = initial.hasComponents ? '' : initial.legacyFullName,
      // Only a separated name can say "no middle name"; a legacy record
      // leaves the box for the patient to decide.
      _noMiddleName = initial.hasComponents && !initial.hasMiddleName;

  bool get noMiddleName => _noMiddleName;

  set noMiddleName(bool value) {
    _noMiddleName = value;
    if (value) {
      middle.clear();
      middleError = null;
    }
    notifyListeners();
  }

  PatientName get value {
    final middleName = PatientName.normalize(middle.text);
    return PatientName(
      firstName: PatientName.normalize(first.text),
      middleName: _noMiddleName || middleName.isEmpty ? null : middleName,
      lastName: PatientName.normalize(last.text),
    );
  }

  static String? _firstNameError(String value) =>
      Validators.validatePersonNamePart(value, fieldLabel: 'First name');

  static String? _lastNameError(String value) =>
      Validators.validatePersonNamePart(value, fieldLabel: 'Last name');

  String? _middleNameError(String value) {
    if (_noMiddleName) return null;
    if (value.trim().isEmpty) {
      return 'Enter your middle name, or tick "I don\'t have a middle name."';
    }
    return Validators.validatePersonNamePart(value, fieldLabel: 'Middle name');
  }

  /// Validates every part and shows the errors. Returns the first message
  /// in field order, or null when the name is complete.
  String? validate() {
    firstError = _firstNameError(first.text);
    middleError = _middleNameError(middle.text);
    lastError = _lastNameError(last.text);
    notifyListeners();
    return firstError ?? middleError ?? lastError;
  }

  // While typing, an empty field shows no error yet.
  void _onFirstChanged(String value) {
    firstError = value.isEmpty ? null : _firstNameError(value);
    notifyListeners();
  }

  void _onMiddleChanged(String value) {
    middleError = value.isEmpty ? null : _middleNameError(value);
    notifyListeners();
  }

  void _onLastChanged(String value) {
    lastError = value.isEmpty ? null : _lastNameError(value);
    notifyListeners();
  }

  @override
  void dispose() {
    first.dispose();
    middle.dispose();
    last.dispose();
    super.dispose();
  }
}

class PatientNameFields extends StatelessWidget {
  final PatientNameController controller;
  final NameFieldDecoration decoration;
  final double spacing;
  final Color labelColor;

  const PatientNameFields({
    super.key,
    required this.controller,
    required this.decoration,
    this.spacing = 16,
    this.labelColor = const Color(0xFF173B4F),
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.legacyFullName.isNotEmpty) ...[
              Text(
                'Saved name: ${controller.legacyFullName}. Please enter it '
                'as separate first, middle, and last names.',
                style: TextStyle(
                  color: labelColor.withValues(alpha: 0.75),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              SizedBox(height: spacing * 0.75),
            ],
            TextField(
              controller: controller.first,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              onChanged: controller._onFirstChanged,
              decoration: decoration(
                'First Name',
                Icons.person_outline,
                controller.firstError,
              ),
            ),
            SizedBox(height: spacing),
            TextField(
              controller: controller.middle,
              enabled: !controller.noMiddleName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.middleName],
              onChanged: controller._onMiddleChanged,
              decoration: decoration(
                'Middle Name',
                Icons.person_outline,
                controller.middleError,
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => controller.noMiddleName = !controller.noMiddleName,
              child: Row(
                children: [
                  Checkbox(
                    value: controller.noMiddleName,
                    onChanged: (value) =>
                        controller.noMiddleName = value ?? false,
                    activeColor: const Color(0xFF2C5F7D),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "I don't have a middle name",
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing * 0.75),
            TextField(
              controller: controller.last,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.familyName],
              onChanged: controller._onLastChanged,
              decoration: decoration(
                'Last Name',
                Icons.badge_outlined,
                controller.lastError,
              ),
            ),
          ],
        );
      },
    );
  }
}
