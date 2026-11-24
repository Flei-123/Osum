/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_MM_H
#define LKPI_LINUX_MM_H
#include <linux/kernel.h>
#include <linux/atomic.h>
#include <linux/slab.h>
#define PAGE_MASK (~(PAGE_SIZE - 1))
struct page { unsigned long flags; unsigned long private; atomic_t refcount; void *virtual; struct page *next; };
#define __GFP_COMP 0U
#define __GFP_NORETRY 0U
#define __GFP_NOMEMALLOC 0U
#define GFP_USER 0U
#define __GFP_HIGHMEM 0U
struct page *alloc_pages(gfp_t gfp, unsigned int order);
void __free_pages(struct page *page, unsigned int order);
void *page_address(const struct page *page);
void get_page(struct page *page);
void put_page(struct page *page);
int page_count(struct page *page);
#define __free_page(p) __free_pages((p), 0)
#define alloc_page(gfp) alloc_pages(gfp, 0)
#define set_page_private(p, v) ((p)->private = (v))
#define page_private(p) ((p)->private)
unsigned long __get_free_pages(gfp_t gfp, unsigned int order);
void free_pages(unsigned long addr, unsigned int order);
int get_order(unsigned long size);
void *kvmalloc(size_t size, gfp_t flags);
void *kvzalloc(size_t size, gfp_t flags);
void kvfree(const void *ptr);
#define kvmalloc_array(n, size, flags) kvmalloc((n) * (size), (flags))
#define kvcalloc(n, size, flags) kvzalloc((n) * (size), (flags))
#endif
