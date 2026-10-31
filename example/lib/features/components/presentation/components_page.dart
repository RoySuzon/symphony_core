import 'package:flutter/material.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/widgets/app_widgets.dart';
import 'component_sections.dart';

/// Showcase of the package's UI module: buttons, inputs, dialogs,
/// snackbars, loading overlay, empty/error states and responsive helpers.
class ComponentsPage extends StatelessWidget {
  /// Creates the page.
  const ComponentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPage(
      title: 'Components',
      scrollable: true,
      maxWidth: 900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ButtonsSection(),
          SizedBox(height: SymphonySpacing.lg),
          InputsSection(),
          SizedBox(height: SymphonySpacing.lg),
          DialogsSection(),
          SizedBox(height: SymphonySpacing.lg),
          SnackbarsSection(),
          SizedBox(height: SymphonySpacing.lg),
          FeedbackSection(),
          SizedBox(height: SymphonySpacing.lg),
          ResponsiveSection(),
          SizedBox(height: SymphonySpacing.lg),
          RoutingSection(),
          SizedBox(height: SymphonySpacing.xl),
        ],
      ),
    );
  }
}
