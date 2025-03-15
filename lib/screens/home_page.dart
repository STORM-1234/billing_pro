import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:billing_pro/database/local_db_helper.dart';  // Import the updated database helper

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Calendar fields
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Database helper instance
  final LocalDbHelper dbHelper = LocalDbHelper();

  // Clock fields
  late String _timeString;
  late String _dayString;
  Timer? _timer;

  // Controller for the sticky note TextField.
  late final TextEditingController _noteController;

  // Cache to hold notes for each day using an ISO8601 date string as key.
  Map<String, String> _notesCache = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _noteController = TextEditingController();
    // Initialize the database and then load notes.
    dbHelper.initDb().then((_) {
      _loadNotesCache();
      _updateNoteController();
    });
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  /// Normalize a date to remove the time component.
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Load note text for the currently selected day from the database.
  Future<void> _updateNoteController() async {
    final normalized = _normalizeDate(_selectedDay ?? DateTime.now());
    final dateStr = normalized.toIso8601String();
    String? note = await dbHelper.getNote(dateStr);
    setState(() {
      _noteController.text = note ?? "";
    });
  }

  /// Load all notes from the database into _notesCache.
  Future<void> _loadNotesCache() async {
    final allNotes = await dbHelper.getAllNotes();
    setState(() {
      _notesCache = allNotes;
    });
  }

  /// Save note for the currently selected day in the database.
  Future<void> _saveNote() async {
    if (_selectedDay == null) return;
    final normalized = _normalizeDate(_selectedDay!);
    final dateStr = normalized.toIso8601String();
    await dbHelper.insertOrUpdateNote(dateStr, _noteController.text);
    // Update the cache for this day.
    if (_noteController.text.trim().isNotEmpty) {
      _notesCache[dateStr] = _noteController.text;
    } else {
      _notesCache.remove(dateStr);
    }
    setState(() {});
  }

  /// Update the time and day strings.
  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timeString = DateFormat('hh:mm:ss a').format(now); // e.g., 07:25:10 PM
      _dayString = DateFormat('EEEE').format(now);         // e.g., Monday
    });
  }

  /// Jump back to today's date.
  void _goToToday() {
    setState(() {
      _focusedDay = DateTime.now();
      _selectedDay = DateTime.now();
      _updateNoteController();
    });
  }

  // Builds a reusable dashboard card.
  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return _DashboardCard(
      icon: icon,
      title: title,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Preserve the gradient background.
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.lightBlueAccent, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT SIDE: Logo, Navigation Cards, and Clock/Day Display.
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Company Logo.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.asset(
                          'lib/Assets/Crown.png',
                          height: 300,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Navigation Cards.
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 20,
                        runSpacing: 20,
                        children: [
                          _buildDashboardCard(
                            icon: Icons.receipt_long,
                            title: 'Invoices',
                            onTap: () => Navigator.pushNamed(context, '/invoices'),
                          ),
                          _buildDashboardCard(
                            icon: Icons.receipt,
                            title: 'Receipts',
                            onTap: () => Navigator.pushNamed(context, '/receipts'),
                          ),
                          _buildDashboardCard(
                            icon: Icons.price_change,
                            title: 'Prices',
                            onTap: () => Navigator.pushNamed(context, '/prices'),
                          ),
                          _buildDashboardCard(
                            icon: Icons.business,
                            title: 'Company',
                            onTap: () => Navigator.pushNamed(context, '/company'),
                          ),
                          // New Ledger Card.
                          _buildDashboardCard(
                            icon: Icons.book,
                            title: 'Ledger',
                            onTap: () => Navigator.pushNamed(context, '/ledger'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      // Clock and Day of the Week Display.
                      Text(
                        _timeString,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dayString,
                        style: const TextStyle(
                          fontSize: 20,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              // RIGHT SIDE: Calendar and Fixed Sticky Note below.
              Container(
                width: 400,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Card with Calendar and "Today" Button.
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "Today" Button.
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Today'),
                                  onPressed: _goToToday,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Calendar in a fixed-height container.
                            SizedBox(
                              height: 400,
                              child: TableCalendar(
                                firstDay: DateTime.utc(2020, 1, 1),
                                lastDay: DateTime.utc(2030, 12, 31),
                                focusedDay: _focusedDay,
                                calendarFormat: _calendarFormat,
                                availableCalendarFormats: const {
                                  CalendarFormat.month: 'Month',
                                },
                                headerStyle: const HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                ),
                                currentDay: DateTime.now(),
                                selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                                onDaySelected: (selectedDay, focusedDay) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                  });
                                  _updateNoteController();
                                },
                                onPageChanged: (focusedDay) {
                                  _focusedDay = focusedDay;
                                },
                                // Custom builders to highlight days with notes.
                                calendarBuilders: CalendarBuilders(
                                  defaultBuilder: (context, day, focusedDay) {
                                    final normalizedDay = _normalizeDate(day);
                                    final dateStr = normalizedDay.toIso8601String();
                                    bool hasNote = _notesCache.containsKey(dateStr) &&
                                        _notesCache[dateStr]!.trim().isNotEmpty;
                                    if (hasNote) {
                                      return Container(
                                        margin: const EdgeInsets.all(6.0),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.amberAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.amberAccent.withOpacity(0.8),
                                              blurRadius: 8.0,
                                              spreadRadius: 1.0,
                                            )
                                          ],
                                        ),
                                        child: Text(
                                          '${day.day}',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }
                                    return null;
                                  },
                                  todayBuilder: (context, day, focusedDay) {
                                    final normalizedDay = _normalizeDate(day);
                                    final dateStr = normalizedDay.toIso8601String();
                                    bool hasNote = _notesCache.containsKey(dateStr) &&
                                        _notesCache[dateStr]!.trim().isNotEmpty;
                                    if (hasNote) {
                                      return Container(
                                        margin: const EdgeInsets.all(6.0),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.amberAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.amberAccent.withOpacity(0.8),
                                              blurRadius: 8.0,
                                              spreadRadius: 1.0,
                                            )
                                          ],
                                          border: Border.all(color: Colors.black, width: 2),
                                        ),
                                        child: Text(
                                          '${day.day}',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }
                                    return Container(
                                      margin: const EdgeInsets.all(6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black, width: 2),
                                      ),
                                      child: Text(
                                        '${day.day}',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    );
                                  },
                                  selectedBuilder: (context, day, focusedDay) {
                                    final normalizedDay = _normalizeDate(day);
                                    final dateStr = normalizedDay.toIso8601String();
                                    bool hasNote = _notesCache.containsKey(dateStr) &&
                                        _notesCache[dateStr]!.trim().isNotEmpty;
                                    if (hasNote) {
                                      return Container(
                                        margin: const EdgeInsets.all(6.0),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.amberAccent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.amberAccent.withOpacity(0.8),
                                              blurRadius: 8.0,
                                              spreadRadius: 1.0,
                                            )
                                          ],
                                          border: Border.all(color: Colors.black, width: 2),
                                        ),
                                        child: Text(
                                          '${day.day}',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }
                                    return Container(
                                      margin: const EdgeInsets.all(6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black, width: 2),
                                      ),
                                      child: Text(
                                        '${day.day}',
                                        style: const TextStyle(color: Colors.black),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Fixed Sticky Note below the calendar.
                    Card(
                      elevation: 6,
                      color: Colors.yellow[100],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Sticky Note",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _noteController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: "Enter note",
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _saveNote,
                              child: const Text("Save"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable dashboard card widget.
class _DashboardCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DashboardCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transformAlignment: Alignment.center,
        transform: _isHovering
            ? (Matrix4.identity()..scale(1.05))
            : Matrix4.identity(),
        child: InkWell(
          onTap: widget.onTap,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 140,
              height: 140,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 40,
                      color: Colors.black,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
