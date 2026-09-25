import 'package:flutter/material.dart';

class GuideSizingPage extends StatefulWidget {
  const GuideSizingPage({super.key});

  @override
  State<GuideSizingPage> createState() => _GuideSizingPageState();
}

class _GuideSizingPageState extends State<GuideSizingPage> {
  final ScrollController _hScrollController = ScrollController();

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💻 Server Hardware Sizing Matrix',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose the right CPU and RAM specs based on your expected user activity and media/calling needs.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Sizing Table with constrained cell widths and soft wrap to prevent bleeding
          Scrollbar(
            controller: _hScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 8),
              child: DataTable(
                columnSpacing: 10,
                horizontalMargin: 10,
                headingRowHeight: 38,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 90,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                border: TableBorder.all(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                columns: const [
                  DataColumn(
                    label: SizedBox(
                      width: 80,
                      child: Text('Scale Tier', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 75,
                      child: Text('Messaging', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 80,
                      child: Text('Voice/Calling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 115,
                      child: Text('Infrastructure Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
                rows: const [
                  DataRow(cells: [
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('Small\n(Family & Friends)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    )),
                    DataCell(SizedBox(
                      width: 75,
                      child: Text('1 vCPU\n1 GB RAM', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('2 GB RAM', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 115,
                      child: Text('TURN relay requires higher memory & CPU during active call streams.', style: TextStyle(fontSize: 10), softWrap: true),
                    )),
                  ]),
                  DataRow(cells: [
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('Medium\n(Community / Team)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    )),
                    DataCell(SizedBox(
                      width: 75,
                      child: Text('2 vCPU\n2 GB RAM', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('2 vCPU\n4 GB RAM', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 115,
                      child: Text('Consider an external TURN relay server if group calling is frequent.', style: TextStyle(fontSize: 10), softWrap: true),
                    )),
                  ]),
                  DataRow(cells: [
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('Large\n(100s Active Users)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    )),
                    DataCell(SizedBox(
                      width: 75,
                      child: Text('4 vCPU\n4 GB+ RAM', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 80,
                      child: Text('Separate TURN Box', style: TextStyle(fontSize: 11)),
                    )),
                    DataCell(SizedBox(
                      width: 115,
                      child: Text('Keep heavy media/TURN relay separated from main SQLite disk host.', style: TextStyle(fontSize: 10), softWrap: true),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
