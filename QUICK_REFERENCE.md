# Quick Reference Guide - Admin Panel Implementation

## 🎯 Core Features

### Dashboard Page Features
```
✅ KPI Cards (3)
   - Total Patients
   - Today's Scheduled
   - Pending Patients

✅ Monthly Growth Chart
   - 6-month trend line chart
   - Uses fl_chart library

✅ Patients List
   - Clickable patient rows
   - Shows name, email, avatar

✅ Patient Modal
   - View full patient details
   - Assign weekly schedule (Mon-Sat)
   - Save to database
```

### Patients Page Features
```
✅ Pending Patients Table
   - Name, Contact, Address
   - Accept/Decline buttons
   
✅ Accepted Patients Table
   - Name, Contact, Status
   - Shows "No Schedule" or "Scheduled"
   
✅ Declined Patients Table
   - Name, Contact
```

---

## 🔧 Backend Integration

### New Supabase Methods
```dart
// Counts
getPendingPatientsCount()
getMonthlyPatientData(months)

// Lists
getPendingPatients()
getAcceptedPatients()
getDeclinedPatients()
getAllPatients()

// Operations
updatePatientStatus(patientId, status)
updatePatientSchedule(patientId, days)
createDialysisSlot(slotData)
getPatientSchedule(patientId)
```

### Database Tables
```
profiles
├─ id
├─ full_name
├─ email
├─ phone
├─ address
├─ blood_type
├─ guardian_name
├─ guardian_contact
├─ status (pending|accepted|declined|no_sched)
├─ role
└─ created_at

dialysis_slots
├─ id
├─ patient_id (FK → profiles.id)
├─ day_of_week (Monday-Saturday)
└─ created_at
```

---

## 🎨 UI Components

### Common Widgets
- `_buildSidebar()` - Navigation sidebar
- `_buildKPICard()` - Statistics cards
- `_buildPatientRow()` - Patient list item
- `_buildPatientModal()` - Detail view

### Colors
```dart
Primary:   #2A5F7E (Dark Teal)
Dark:      #1A4A63 (Darker Teal)
Light BG:  #F5F7FA (Light Gray)
Text:      #2D3748 (Dark Gray)
Secondary: #718096 (Medium Gray)
```

---

## 📱 Page Navigation

```
Login → Dashboard → (Patient Click) → Modal
                 → Patients Page → Accept/Decline
                 → Appointments Page
```

---

## 🚀 Running the App

### Prerequisites
```bash
# Get dependencies
flutter pub get

# Check for errors
flutter analyze

# Run on device/emulator
flutter run
```

### Environment Variables
Ensure `.env` contains:
```
SUPABASE_URL=your_url
SUPABASE_ANON_KEY=your_key
```

---

## 📊 Data Flow

```
Dashboard Load
    ↓
Load 5 Futures in Parallel:
  - totalPatients
  - todaysAppointmentsCount
  - pendingPatientsCount
  - monthlyData
  - allPatients
    ↓
FutureBuilders Display Data
    ↓
User Clicks Patient
    ↓
Modal Shows with Details
    ↓
User Selects Schedule Days
    ↓
Save → updatePatientSchedule()
    ↓
Insert into dialysis_slots
    ↓
SnackBar Confirmation
```

---

## 🔍 Common Operations

### Accept a Patient
```dart
await _service.updatePatientStatus(patientId, 'no_sched');
```

### Decline a Patient
```dart
await _service.updatePatientStatus(patientId, 'declined');
```

### Save Patient Schedule
```dart
await _service.updatePatientSchedule(patientId, selectedDays);
// Example: ['Monday', 'Wednesday', 'Friday']
```

### Get Pending Patients
```dart
final pending = await _service.getPendingPatients();
```

---

## 🐛 Debugging

### Check Supabase Connection
```dart
// In main.dart or init
await Supabase.initialize(url: url, anonKey: key);
```

### View Database Queries
- Check print statements in service methods
- Use Supabase Dashboard to verify data

### Animation Issues
- Check TickerProviderStateMixin is mixed in
- Verify dispose() is called

### Modal Not Showing
- Ensure BuildContext is correct
- Check Navigator is properly initialized

---

## 📝 File Locations

```
admin_panel/
├─ lib/
│  ├─ features/
│  │  ├─ dashboard/
│  │  │  └─ dashboard_page.dart ✨ UPDATED
│  │  ├─ patients/
│  │  │  └─ patients_page.dart ✨ UPDATED
│  │  └─ appointments/
│  ├─ models/
│  │  └─ patient.dart ✨ UPDATED
│  ├─ services/
│  │  └─ supabase_service.dart ✨ UPDATED
│  └─ main.dart
└─ pubspec.yaml ✨ UPDATED
```

---

## ✨ Key Improvements Made

| Feature | Before | After |
|---------|--------|-------|
| Header | Blue bar with icons | Clean white space |
| KPIs | 3 clinic cards | 3 patient metrics |
| Graph | Not present | Monthly trend chart |
| Patient View | Static list | Clickable with modal |
| Schedule | Not available | Full week selector |
| Patients Page | Placeholder | 3 sections w/ tables |
| Animations | Basic | Smooth fades & scales |

---

## 🎓 Learning Resources

### Flutter Documentation
- [FutureBuilder](https://api.flutter.dev/flutter/widgets/FutureBuilder-class.html)
- [DataTable](https://api.flutter.dev/flutter/material/DataTable-class.html)
- [Animation Guide](https://flutter.dev/docs/development/ui/animations)

### Supabase Docs
- [Supabase Flutter Guide](https://supabase.com/docs/reference/dart)
- [Supabase RLS Policies](https://supabase.com/docs/guides/auth/row-level-security)

### fl_chart Documentation
- [fl_chart Pub.dev](https://pub.dev/packages/fl_chart)

---

**Last Updated**: May 1, 2026
**Status**: ✅ Production Ready
**Version**: 1.0.0
