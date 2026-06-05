import 'package:flutter/material.dart';

class FakturHeaderSection extends StatelessWidget {
  const FakturHeaderSection({
    super.key,
    required this.fakturHeading,
    required this.branchTitleFuture,
    required this.dense,
  });

  final String fakturHeading;
  final Future<String> branchTitleFuture;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          fakturHeading,
          textAlign: TextAlign.center,
          style: (dense
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineMedium)
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        FutureBuilder<String>(
          future: branchTitleFuture,
          builder: (context, snapshot) {
            final title =
                (snapshot.data?.toString().trim().isNotEmpty ?? false)
                    ? snapshot.data!.toString().trim()
                    : 'VANESSA GOLD & DIAMOND';
            return Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            );
          },
        ),
        Divider(height: dense ? 12 : 32, thickness: dense ? 1 : 2),
      ],
    );
  }
}
