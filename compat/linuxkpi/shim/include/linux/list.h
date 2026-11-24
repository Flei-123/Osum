/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_LIST_H
#define LKPI_LINUX_LIST_H
#include <linux/kernel.h>
struct list_head { struct list_head *next, *prev; };
#define LIST_HEAD_INIT(name) { &(name), &(name) }
#define LIST_HEAD(name) struct list_head name = LIST_HEAD_INIT(name)
static inline void INIT_LIST_HEAD(struct list_head *l) { l->next = l; l->prev = l; }
static inline void __list_add(struct list_head *n, struct list_head *prev, struct list_head *next) { next->prev = n; n->next = next; n->prev = prev; prev->next = n; }
static inline void list_add(struct list_head *n, struct list_head *head) { __list_add(n, head, head->next); }
static inline void list_add_tail(struct list_head *n, struct list_head *head) { __list_add(n, head->prev, head); }
static inline void list_del(struct list_head *e) { e->next->prev = e->prev; e->prev->next = e->next; e->next = e; e->prev = e; }
static inline void list_del_init(struct list_head *e) { list_del(e); }
static inline int list_empty(const struct list_head *h) { return h->next == h; }
static inline void list_move_tail(struct list_head *e, struct list_head *head) { list_del(e); list_add_tail(e, head); }
static inline void list_move(struct list_head *e, struct list_head *head) { list_del(e); list_add(e, head); }
static inline void list_replace(struct list_head *old, struct list_head *n) { n->next = old->next; n->next->prev = n; n->prev = old->prev; n->prev->next = n; }
static inline void list_replace_init(struct list_head *old, struct list_head *n) { list_replace(old, n); INIT_LIST_HEAD(old); }
static inline void list_splice_tail(const struct list_head *list, struct list_head *head)
{
	if (list_empty(list))
		return;
	list->next->prev = head->prev;
	head->prev->next = list->next;
	list->prev->next = head;
	head->prev = list->prev;
}
static inline void list_splice_tail_init(struct list_head *list, struct list_head *head) { list_splice_tail(list, head); INIT_LIST_HEAD(list); }
#define list_entry(ptr, type, member) container_of(ptr, type, member)
#define list_first_entry(ptr, type, member) list_entry((ptr)->next, type, member)
#define list_first_entry_or_null(ptr, type, member) (list_empty(ptr) ? NULL : list_first_entry(ptr, type, member))
#define list_next_entry(pos, member) list_entry((pos)->member.next, __typeof__(*(pos)), member)
#define list_for_each_entry(pos, head, member) \
	for (pos = list_first_entry(head, __typeof__(*pos), member); &pos->member != (head); pos = list_next_entry(pos, member))
#define list_for_each_entry_safe(pos, n, head, member) \
	for (pos = list_first_entry(head, __typeof__(*pos), member), n = list_next_entry(pos, member); \
	     &pos->member != (head); pos = n, n = list_next_entry(n, member))
#endif
