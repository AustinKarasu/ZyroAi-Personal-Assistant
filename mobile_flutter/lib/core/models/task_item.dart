class TaskItem {
  final String id;
  final String title;
  final int priorityScore;

  TaskItem({required this.id, required this.title, required this.priorityScore});

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String,
      priorityScore: json['priority_score'] as int,
    );
  }
}
