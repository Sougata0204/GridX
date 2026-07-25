// GridX³ — DPI-C Memory Model Backend (C Implementation)
// Sparse memory model using a hash map. Only touched pages consume memory.
// Compile: gcc -shared -fPIC -o libgridx_mem.so gridx_mem_model.c
// Or for XSIM: include in xvlog -sv -dpiheader commands

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---- Configuration ----
#define MAX_MEM_INSTANCES  16
#define PAGE_SIZE          4096      // Bytes per page
#define PAGE_SHIFT         12       // log2(PAGE_SIZE)
#define HASH_TABLE_SIZE    65536    // Hash buckets
#define MAX_PAGES          262144   // Max pages per instance (1 GB)

// ---- Page Entry ----
typedef struct page_entry {
    unsigned int          page_num;
    unsigned char         data[PAGE_SIZE];
    struct page_entry    *next;     // Chaining for hash collisions
} page_entry_t;

// ---- Memory Instance ----
typedef struct {
    page_entry_t *hash_table[HASH_TABLE_SIZE];
    int           page_count;
    int           initialized;
} mem_instance_t;

static mem_instance_t instances[MAX_MEM_INSTANCES];

// ---- Hash function ----
static unsigned int page_hash(unsigned int page_num) {
    return page_num % HASH_TABLE_SIZE;
}

// ---- Find or allocate a page ----
static page_entry_t* find_or_alloc_page(mem_instance_t *inst, unsigned int page_num, int allocate) {
    unsigned int h = page_hash(page_num);
    page_entry_t *entry = inst->hash_table[h];

    // Search chain
    while (entry) {
        if (entry->page_num == page_num)
            return entry;
        entry = entry->next;
    }

    if (!allocate)
        return NULL;

    // Allocate new page
    if (inst->page_count >= MAX_PAGES) {
        fprintf(stderr, "[MEM_MODEL] ERROR: Max pages (%d) exceeded\n", MAX_PAGES);
        return NULL;
    }

    entry = (page_entry_t *)calloc(1, sizeof(page_entry_t));
    if (!entry) {
        fprintf(stderr, "[MEM_MODEL] ERROR: malloc failed\n");
        return NULL;
    }

    entry->page_num = page_num;
    entry->next = inst->hash_table[h];
    inst->hash_table[h] = entry;
    inst->page_count++;
    return entry;
}

// ---- DPI-C: Initialize memory instance ----
void mem_model_init(int mem_id, const char *init_file) {
    if (mem_id < 0 || mem_id >= MAX_MEM_INSTANCES) {
        fprintf(stderr, "[MEM_MODEL] ERROR: Invalid mem_id %d\n", mem_id);
        return;
    }

    mem_instance_t *inst = &instances[mem_id];
    memset(inst->hash_table, 0, sizeof(inst->hash_table));
    inst->page_count = 0;
    inst->initialized = 1;

    // Load init file if provided
    if (init_file && strlen(init_file) > 0) {
        FILE *fp = fopen(init_file, "r");
        if (fp) {
            unsigned int addr, data;
            while (fscanf(fp, "%x %x", &addr, &data) == 2) {
                unsigned int pn = addr >> PAGE_SHIFT;
                unsigned int offset = addr & (PAGE_SIZE - 1);
                page_entry_t *page = find_or_alloc_page(inst, pn, 1);
                if (page) page->data[offset] = (unsigned char)data;
            }
            fclose(fp);
            fprintf(stderr, "[MEM_MODEL %d] Loaded init file: %s (%d pages)\n",
                    mem_id, init_file, inst->page_count);
        }
    }

    fprintf(stderr, "[MEM_MODEL %d] Initialized (sparse hash, max %d pages = %d MB)\n",
            mem_id, MAX_PAGES, (MAX_PAGES * PAGE_SIZE) / (1024*1024));
}

// ---- DPI-C: Write 256-bit block ----
void mem_model_write(int mem_id, long long addr, int d0, int d1, int d2, int d3, int d4, int d5, int d6, int d7) {
    if (mem_id < 0 || mem_id >= MAX_MEM_INSTANCES) return;
    mem_instance_t *inst = &instances[mem_id];
    if (!inst->initialized) return;

    unsigned long long uaddr = (unsigned long long)addr;
    unsigned int pn = uaddr >> PAGE_SHIFT;
    unsigned int offset = uaddr & (PAGE_SIZE - 1);
    
    printf("[C_MEM %d] WRITE addr=0x%llx (page=%u, offset=%u) data=0x%08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x\n",
           mem_id, uaddr, pn, offset, d7, d6, d5, d4, d3, d2, d1, d0);
    fflush(stdout);
           
    page_entry_t *page = find_or_alloc_page(inst, pn, 1);
    if (page) {
        // Ensure we do not write past page boundary (assume 32-byte alignment)
        if (offset + 32 <= PAGE_SIZE) {
            memcpy(&page->data[offset],      &d0, 4);
            memcpy(&page->data[offset + 4],  &d1, 4);
            memcpy(&page->data[offset + 8],  &d2, 4);
            memcpy(&page->data[offset + 12], &d3, 4);
            memcpy(&page->data[offset + 16], &d4, 4);
            memcpy(&page->data[offset + 20], &d5, 4);
            memcpy(&page->data[offset + 24], &d6, 4);
            memcpy(&page->data[offset + 28], &d7, 4);
        } else {
            // Unaligned write handling (byte-by-byte to be safe)
            int data_arr[8] = {d0, d1, d2, d3, d4, d5, d6, d7};
            unsigned char *byte_ptr = (unsigned char *)data_arr;
            for (unsigned int i = 0; i < 32; i++) {
                unsigned int curr_offset = offset + i;
                unsigned int curr_pn = pn;
                if (curr_offset >= PAGE_SIZE) {
                    curr_pn++;
                    curr_offset -= PAGE_SIZE;
                }
                page_entry_t *curr_page = find_or_alloc_page(inst, curr_pn, 1);
                if (curr_page) curr_page->data[curr_offset] = byte_ptr[i];
            }
        }
    }
}

// ---- DPI-C: Read 256-bit block ----
void mem_model_read(int mem_id, long long addr, int *d0, int *d1, int *d2, int *d3, int *d4, int *d5, int *d6, int *d7) {
    if (mem_id < 0 || mem_id >= MAX_MEM_INSTANCES || !d0) return;
    mem_instance_t *inst = &instances[mem_id];
    if (!inst->initialized) {
        *d0 = *d1 = *d2 = *d3 = *d4 = *d5 = *d6 = *d7 = 0;
        return;
    }

    unsigned long long uaddr = (unsigned long long)addr;
    unsigned int pn = uaddr >> PAGE_SHIFT;
    unsigned int offset = uaddr & (PAGE_SIZE - 1);
    page_entry_t *page = find_or_alloc_page(inst, pn, 0);
    
    if (offset + 32 <= PAGE_SIZE) {
        if (!page) {
            *d0 = *d1 = *d2 = *d3 = *d4 = *d5 = *d6 = *d7 = 0;
            printf("[C_MEM %d] READ addr=0x%llx (page=%u, offset=%u) NOT FOUND (returned 0)\n", mem_id, uaddr, pn, offset);
            fflush(stdout);
            return;
        }
        memcpy(d0, &page->data[offset],      4);
        memcpy(d1, &page->data[offset + 4],  4);
        memcpy(d2, &page->data[offset + 8],  4);
        memcpy(d3, &page->data[offset + 12], 4);
        memcpy(d4, &page->data[offset + 16], 4);
        memcpy(d5, &page->data[offset + 20], 4);
        memcpy(d6, &page->data[offset + 24], 4);
        memcpy(d7, &page->data[offset + 28], 4);
        printf("[C_MEM %d] READ addr=0x%llx (page=%u, offset=%u) FOUND data=0x%08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x\n",
               mem_id, uaddr, pn, offset, *d7, *d6, *d5, *d4, *d3, *d2, *d1, *d0);
        fflush(stdout);
    } else {
        // Unaligned read handling
        int data_arr[8] = {0};
        unsigned char *byte_ptr = (unsigned char *)data_arr;
        for (unsigned int i = 0; i < 32; i++) {
            unsigned int curr_offset = offset + i;
            unsigned int curr_pn = pn;
            if (curr_offset >= PAGE_SIZE) {
                curr_pn++;
                curr_offset -= PAGE_SIZE;
            }
            page_entry_t *curr_page = find_or_alloc_page(inst, curr_pn, 0);
            byte_ptr[i] = curr_page ? curr_page->data[curr_offset] : 0;
        }
        *d0 = data_arr[0];
        *d1 = data_arr[1];
        *d2 = data_arr[2];
        *d3 = data_arr[3];
        *d4 = data_arr[4];
        *d5 = data_arr[5];
        *d6 = data_arr[6];
        *d7 = data_arr[7];
        printf("[C_MEM %d] READ addr=0x%llx (page=%u, offset=%u) UNALIGNED data=0x%08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x\n",
               mem_id, uaddr, pn, offset, *d7, *d6, *d5, *d4, *d3, *d2, *d1, *d0);
        fflush(stdout);
    }
}

// ---- DPI-C: Get page count ----
int mem_model_pages(int mem_id) {
    if (mem_id < 0 || mem_id >= MAX_MEM_INSTANCES) return 0;
    return instances[mem_id].page_count;
}

// ---- DPI-C: Destroy instance ----
void mem_model_destroy(int mem_id) {
    if (mem_id < 0 || mem_id >= MAX_MEM_INSTANCES) return;
    mem_instance_t *inst = &instances[mem_id];

    for (int i = 0; i < HASH_TABLE_SIZE; i++) {
        page_entry_t *entry = inst->hash_table[i];
        while (entry) {
            page_entry_t *next = entry->next;
            free(entry);
            entry = next;
        }
        inst->hash_table[i] = NULL;
    }

    fprintf(stderr, "[MEM_MODEL %d] Destroyed (%d pages freed)\n",
            mem_id, inst->page_count);
    inst->page_count = 0;
    inst->initialized = 0;
}
