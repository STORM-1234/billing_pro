import 'package:flutter/material.dart';

/// A basic search delegate for a list of items
class PricesSearchDelegate extends SearchDelegate<String?> {
  /// The full list of item names (or item maps).
  final List<String> allItemNames;

  PricesSearchDelegate({required this.allItemNames});

  /// Called when the user clears the search (the 'x' icon)
  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      // Clear input
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  /// Called when the user presses the back arrow
  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null); // Return null => no selection
      },
    );
  }

  /// The main results shown under the search bar
  @override
  Widget buildResults(BuildContext context) {
    // For partial match ignoring case:
    final qLower = query.toLowerCase();
    final results = allItemNames.where((name) {
      return name.toLowerCase().contains(qLower);
    }).toList();

    if (results.isEmpty) {
      return const Center(
        child: Text("No results found."),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final itemName = results[index];
        return ListTile(
          title: Text(itemName),
          onTap: () {
            // Return the selected item
            close(context, itemName);
          },
        );
      },
    );
  }

  /// Called as the user types. Often you can show "suggestions" here.
  /// We can do the same partial match approach for suggestions.
  @override
  Widget buildSuggestions(BuildContext context) {
    // Show partial matches as suggestions
    final qLower = query.toLowerCase();
    final suggestions = allItemNames.where((name) {
      return name.toLowerCase().contains(qLower);
    }).toList();

    if (suggestions.isEmpty) {
      return const Center(
        child: Text("No suggestions."),
      );
    }

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return ListTile(
          title: Text(suggestion),
          onTap: () {
            // If user taps a suggestion, fill the search field
            query = suggestion;
            // Then show results
            showResults(context);
          },
        );
      },
    );
  }
}
