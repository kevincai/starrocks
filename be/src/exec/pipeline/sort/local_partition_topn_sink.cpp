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

#include "exec/pipeline/sort/local_partition_topn_sink.h"

#include <utility>

namespace starrocks::pipeline {

LocalPartitionTopnSinkOperator::LocalPartitionTopnSinkOperator(OperatorFactory* factory, int32_t id,
                                                               int32_t plan_node_id, int32_t driver_sequence,
                                                               LocalPartitionTopnContext* partition_topn_ctx)
        : Operator(factory, id, "local_partition_topn_sink", plan_node_id, false, driver_sequence),
          _partition_topn_ctx(partition_topn_ctx) {}

Status LocalPartitionTopnSinkOperator::prepare(RuntimeState* state) {
    RETURN_IF_ERROR(Operator::prepare(state));
    _partition_topn_ctx->observable().attach_sink_observer(state, observer());
    return _partition_topn_ctx->prepare(state, _unique_metrics.get());
}

StatusOr<ChunkPtr> LocalPartitionTopnSinkOperator::pull_chunk(RuntimeState* state) {
    return Status::InternalError("Shouldn't call pull_chunk from local partition topn sink operator.");
}

Status LocalPartitionTopnSinkOperator::push_chunk(RuntimeState* state, const ChunkPtr& chunk) {
    auto notify = _partition_topn_ctx->observable().defer_notify_source();
    return _partition_topn_ctx->push_one_chunk_to_partitioner(state, chunk);
}

Status LocalPartitionTopnSinkOperator::set_finishing(RuntimeState* state) {
    auto notify = _partition_topn_ctx->observable().defer_notify_source();
    ONCE_DETECT(_set_finishing_once);
    DeferOp defer([&]() {
        _partition_topn_ctx->sink_complete();
        _unique_metrics->add_info_string("IsPassThrough", _partition_topn_ctx->is_passthrough() ? "Yes" : "No");
        auto* partition_num_counter = ADD_COUNTER(_unique_metrics, "PartitionNum", TUnit::UNIT);
        COUNTER_SET(partition_num_counter, static_cast<int64_t>(_partition_topn_ctx->num_partitions()));
        _is_finished = true;
    });
    if (state->is_cancelled()) {
        return Status::OK();
    }
    return _partition_topn_ctx->transfer_all_chunks_from_partitioner_to_sorters(state);
}

// try to passthrough when memory usage is high.
void LocalPartitionTopnSinkOperator::set_execute_mode(int performance_level) {
    _partition_topn_ctx->set_passthrough();
}

OperatorPtr LocalPartitionTopnSinkOperatorFactory::create(int32_t degree_of_parallelism, int32_t driver_sequence) {
    return std::make_shared<LocalPartitionTopnSinkOperator>(this, _id, _plan_node_id, driver_sequence,
                                                            _partition_topn_ctx_factory->create(driver_sequence));
}

Status LocalPartitionTopnSinkOperatorFactory::prepare(RuntimeState* state) {
    return _partition_topn_ctx_factory->prepare(state);
}

}; // namespace starrocks::pipeline
