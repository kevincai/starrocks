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

#pragma once

#include <atomic>
#include <condition_variable>
#include <list>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

#include "common/status.h"

namespace starrocks::lake {

class Metacache;

class SegmentCacheUpdater {
public:
    explicit SegmentCacheUpdater(Metacache* metacache);
    ~SegmentCacheUpdater();

    void stop();
    void update(const std::string& segment_path, intptr_t segment_ptr);

private:
    void _start();
    void _run();
    void _process_tasks();

    Metacache* _metacache;
    std::atomic<bool> _stopped{true};
    std::thread _thread;
    std::mutex _mutex;
    std::condition_variable _cv;
    std::list<std::pair<std::string, intptr_t>> _segments;
};

} // namespace starrocks::lake
