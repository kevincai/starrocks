// Copyright 2021-present StarRocks, Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "storage/lake/segment_cache_updater.h"

#include <chrono>

#include "storage/lake/metacache.h"
#include "storage/rowset/segment.h"
#include "util/thread.h"

namespace starrocks::lake {

SegmentCacheUpdater::SegmentCacheUpdater(Metacache* metacache) : _metacache(metacache) {
    _start();
}

SegmentCacheUpdater::~SegmentCacheUpdater() {
    stop();
}

void SegmentCacheUpdater::_start() {
    bool expected = true;
    if (_stopped.compare_exchange_strong(expected, false)) {
        _thread = std::thread(&SegmentCacheUpdater::_run, this);
        Thread::set_thread_name(_thread.native_handle(), "seg_cache_updater");
    }
}

void SegmentCacheUpdater::stop() {
    bool expected = false;
    if (!_stopped.compare_exchange_strong(expected, true)) {
        return; // Already stopped
    }
    _cv.notify_all();
    if (_thread.joinable()) {
        _thread.join();
    }
}

void SegmentCacheUpdater::update(const std::string& segment_path, intptr_t segment_ptr) {
    std::lock_guard<std::mutex> l(_mutex);
    _segments.emplace_back(segment_path, segment_ptr);
}

void SegmentCacheUpdater::_run() {
    // wake up every second to process tasks
    auto wait_timeout = std::chrono::seconds(1);
    while (!_stopped) {
        {
            std::unique_lock<std::mutex> l(_mutex);
            _cv.wait_for(l, wait_timeout, [this] { return _stopped.load(); });
        }
        if (_stopped) {
            break;
        }
        _process_tasks();
    }
}

void SegmentCacheUpdater::_process_tasks() {
    std::list<std::pair<std::string, intptr_t>> tasks;
    {
        std::lock_guard<std::mutex> l(_mutex);
        tasks.swap(_segments);
    }

    std::set<std::string> processed_paths;
    for (const auto& task : tasks) {
        if (_stopped) {
            return;
        }

        // already processed, skip it, ignore the intptr_t hint
        // because the segment path is in the processed_paths, so it must exist in the cache
        // if intptr_t_hint == segment, it's a duplicate request, no need to do it again
        // if intptr_t_hint != segment, it means the segment is not present in the cache, `cache_segment_if_present` will do nothing
        if (processed_paths.find(task.first) != processed_paths.end()) {
            continue;
        }

        auto seg = _metacache->lookup_segment(task.first);
        if (seg == nullptr) {
            continue;
        }
        if (task.second != 0 && reinterpret_cast<intptr_t>(seg.get()) != task.second) {
            continue;
        }

        auto mem_cost = seg->mem_usage();
        auto done = _metacache->cache_segment_if_present(task.first, mem_cost, task.second);
        if (done != 0) {
            processed_paths.insert(task.first);
        }
    }
}

} // namespace starrocks::lake
