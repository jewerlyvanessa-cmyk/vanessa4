# Code Citations

## License: unknown
https://github.com/LazarousDeredza/integritylink/tree/f91fa2ad99d3a5113f701e857611ef4a7f0440ec/lib/src/features/core/screens/data_screen/document_comments_screen.dart

```
),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.
```


## License: unknown
https://github.com/Tugas-Akhir-Hakim-dan-Feby/Mobile/tree/6ee41ccd9e6d9f8b7860ce6af6d8b3058bbfd70b/lib/page/profile/member/payment_history/a

```
if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else {
          final
```


## License: unknown
https://github.com/MortalEGY/Sparks-Foundation-Tasks/tree/ec271d8307d3a5c53e3d0597aafc216bcfe56b1d/bank_system_app/lib/main.dart

```
ListView.builder(
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customer = customers[index];
              return ListTile(
                title: Text(customer['name']),
                subtitle: Text(customer['email']),
                trailing:
```

